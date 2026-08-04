//
//  HRequestManager.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

/// Global actor to manage shared mutable state in a thread-safe way.
/// This actor ensures that Harbor's internal state is accessed safely across concurrent contexts.
@globalActor public actor HRequestManagerActor {
    /// The shared instance of the actor.
    public static let shared = HRequestManagerActor()
}

@HRequestManagerActor
final class HRequestManager: Sendable {
    /// Connectivity monitor used as a pre-check before executing requests.
    /// Owned here (typed as the protocol) so tests can substitute a fake.
    static var connectivityMonitor: any HRequestManagerMonitorProtocol = HRequestManagerMonitor()
}

// MARK: - Request With Result
extension HRequestManager {
    static func request<Model: HModel>(model: Model.Type, request: any HRequestWithResultProtocol) async -> HResponseWithResult<Model> {
        if let mock = HMocker.mock(request: request), HConfig.shared.mocksEnabled {
            if let delay = mock.delay {
                let delayInNanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delayInNanoseconds)
            }

            if let hError = mock.error {
                logError(hError, request: request)
                return .error(hError)
            }

            let data = mock.jsonResponse?.data(using: .utf8) ?? Data()
            let mockResponse = HTTPURLResponse(url: mockURL(for: request), statusCode: mock.statusCode, httpVersion: nil, headerFields: mock.headers)
            return await HRequestManager.processResponse(model: model, request: request, statusCode: mock.statusCode, data: data, httpResponse: mockResponse)
        }

        if !connectivityMonitor.isConnectedToNetwork() {
            if let getRequest = request as? any HGetRequestProtocol,
               let stale = await getRequest.staleCacheOnError() as? Model {
                return .success(stale)
            }
            let hError: HRequestError = .noConnection
            logError(hError, request: request)
            return .error(hError)
        }

        guard let modifiedRequest = await addAuthCredentialsIfNeeded(request) as? (any HRequestWithResultProtocol) else {
            let hError: HRequestError = .authProviderNeeded
            logError(hError, request: request)
            return .error(hError)
        }

        let result = await requestHandler(model: model, request: modifiedRequest)
        return result
    }

    private static func requestHandler<Model: HModel>(model: Model.Type, request: any HRequestWithResultProtocol) async -> HResponseWithResult<Model> {
        guard let urlRequest = await HURLBuilder.buildUrlRequest(request: request) else {
            let hError: HRequestError = .malformedRequest
            logError(hError, request: request)
            return .error(hError)
        }

        if let request = request as? HDebugRequestProtocol {
            request.logRequest(urlRequest: urlRequest)
        }

        do {
            let session = getURLSession(for: request)

            // Sessions built internally are single-use; a user-provided session is left untouched.
            let isCustomSession = session === HConfig.shared.customURLSession
            defer { if !isCustomSession { session.finishTasksAndInvalidate() } }

            let startTime = Date()

            let (data, httpResponse) = try await session.data(for: urlRequest)

            let duration = Date().timeIntervalSince(startTime) * 1000

            guard let httpResponse = httpResponse as? HTTPURLResponse else {
                if let retries = request.retries, retries > 0 {
                    var mutableRequest = request
                    mutableRequest.retries = retries - 1
                    return await self.request(model: model, request: mutableRequest)
                } else {
                    let hError: HRequestError = .invalidHttpResponse
                    logError(hError, request: request)
                    return .error(hError)
                }
            }

            if let request = request as? HDebugRequestProtocol {
                request.logResponse(httpResponse: httpResponse, data: data, duration: duration)
            }

            return await processResponse(model: model,
                                         request: request,
                                         statusCode: httpResponse.statusCode,
                                         data: data,
                                         httpResponse: httpResponse)
        } catch let error as URLError {
            if error.code != .cancelled,
               !Task.isCancelled,
               let getRequest = request as? any HGetRequestProtocol,
               let stale = await getRequest.staleCacheOnError() as? Model {
                return .success(stale)
            }
            return .error(HRequestError.mapURLError(error))
        } catch {
            let hError: HRequestError = .invalidRequest
            logError(hError, request: request)
            return .error(hError)
        }
    }

    static func processResponse<Model: HModel>(model: Model.Type, request: any HRequestWithResultProtocol, statusCode: Int, data: Data, httpResponse: HTTPURLResponse? = nil) async -> HResponseWithResult<Model> {
        switch statusCode {
        case 200 ... 299:
            do {
                let parsedResponse = try request.parseData(data: data, model: model)

                if let request = request as? any HGetRequestProtocol {
                    await request.saveCache(data, response: httpResponse)
                }

                return .success(parsedResponse)
            } catch let parseError {
                let hError: HRequestError = .codable(modelName: "\(model.self)", error: parseError)
                logError(hError, request: request)
                return .error(hError)
            }
        case 304:
            // Not Modified — serve the cached body and refresh the stored entry.
            // (URLCache revalidates transparently at URLSession level; this branch handles the custom cache.)
            if let getRequest = request as? any HGetRequestProtocol,
               let cachedAny = await getRequest.revalidatedCache(response: httpResponse),
               let cachedModel = cachedAny as? Model {
                return .success(cachedModel)
            } else {
                let hError: HRequestError = .api(statusCode: statusCode, data: data)
                logError(hError, request: request)
                return .error(hError)
            }
        case 401:
            if await !hasNewAuthorizationHeader(request: request) {
                await HConfig.shared.authProvider?.authFailed()
                let hError: HRequestError = .authNeeded
                logError(hError, request: request)
                return .error(hError)
            } else {
                return await self.request(model: model, request: request)
            }
        default:
            if let retries = request.retries, retries > 0 {
                var mutableRequest = request
                mutableRequest.retries = retries - 1
                return await self.request(model: model, request: mutableRequest)
            } else {
                if statusCode >= 500,
                   let getRequest = request as? any HGetRequestProtocol,
                   let stale = await getRequest.staleCacheOnError() as? Model {
                    return .success(stale)
                }
                let hError: HRequestError = .api(statusCode: statusCode, data: data)
                logError(hError, request: request)
                return .error(hError)
            }
        }
    }
}

// MARK: - Request Without Result
extension HRequestManager {
    static func request(request: any HRequestWithEmptyResponseProtocol) async -> HResponse {
        if let mock = HMocker.mock(request: request), HConfig.shared.mocksEnabled {
            if let delay = mock.delay {
                let delayInNanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delayInNanoseconds)
            }

            if let hError = mock.error {
                logError(hError, request: request)
                return .error(hError)
            }

            let data = mock.jsonResponse?.data(using: .utf8) ?? Data()
            return await HRequestManager.processResponse(request: request, statusCode: mock.statusCode, data: data)
        }

        if !connectivityMonitor.isConnectedToNetwork() {
            let hError: HRequestError = .noConnection
            logError(hError, request: request)
            return .error(hError)
        }

        guard let modifiedRequest = await addAuthCredentialsIfNeeded(request) as? (any HRequestWithEmptyResponseProtocol) else {
            let hError: HRequestError = .authProviderNeeded
            logError(hError, request: request)
            return .error(hError)
        }

        let result = await requestHandler(request: modifiedRequest)
        return result
    }

    private static func requestHandler<P: HRequestWithEmptyResponseProtocol>(request: P) async -> HResponse {
        guard let urlRequest = await HURLBuilder.buildUrlRequest(request: request) else {
            let hError: HRequestError = .malformedRequest
            logError(hError, request: request)
            return .error(hError)
        }

        if let request = request as? HDebugRequestProtocol {
            request.logRequest(urlRequest: urlRequest)
        }

        do {
            let session = getURLSession(for: request)

            // Sessions built internally are single-use; a user-provided session is left untouched.
            let isCustomSession = session === HConfig.shared.customURLSession
            defer { if !isCustomSession { session.finishTasksAndInvalidate() } }

            let startTime = Date()

            let (data, httpResponse) = try await session.data(for: urlRequest)

            let duration = Date().timeIntervalSince(startTime) * 1000

            guard let httpResponse = httpResponse as? HTTPURLResponse else {
                if let retries = request.retries, retries > 0 {
                    var mutableRequest = request
                    mutableRequest.retries = retries - 1
                    return await self.request(request: mutableRequest)
                } else {
                    let hError: HRequestError = .invalidHttpResponse
                    logError(hError, request: request)
                    return .error(hError)
                }
            }

            if let request = request as? HDebugRequestProtocol {
                request.logResponse(httpResponse: httpResponse, data: data, duration: duration)
            }

            return await processResponse(request: request, statusCode: httpResponse.statusCode, data: data)
        } catch let error as URLError {
            return .error(HRequestError.mapURLError(error))
        } catch {
            let hError: HRequestError = .invalidRequest
            logError(hError, request: request)
            return .error(hError)
        }
    }

    static func processResponse(request: HRequestWithEmptyResponseProtocol, statusCode: Int, data: Data) async -> HResponse {
        switch statusCode {
        case 200 ... 299:
            return .success
        case 304:
            // Not Modified — the cached representation is still valid; there is no body to serve.
            return .success
        case 401:
            if await !hasNewAuthorizationHeader(request: request) {
                await HConfig.shared.authProvider?.authFailed()
                let hError: HRequestError = .authNeeded
                logError(hError, request: request)
                return .error(hError)
            } else {
                return await self.request(request: request)
            }
        default:
            if let retries = request.retries, retries > 0 {
                var mutableRequest = request
                mutableRequest.retries = retries - 1
                return await self.request(request: mutableRequest)
            } else {
                let hError: HRequestError = .api(statusCode: statusCode, data: data)
                logError(hError, request: request)
                return .error(hError)
            }
        }
    }
}

// MARK: - Request Builder Functions
extension HRequestManager {
    static func addAuthCredentialsIfNeeded(_ request: any HRequestBaseRequestProtocol) async -> (any HRequestBaseRequestProtocol)? {
        if request.needsAuth {
            var modifiedRequest = request
            if let authCredential = await HConfig.shared.authProvider?.getAuthorizationHeader() {
                if modifiedRequest.headerParameters == nil {
                    modifiedRequest.headerParameters = [:]
                }
                modifiedRequest.headerParameters?[authCredential.key] = authCredential.value
                return modifiedRequest
            } else {
                return nil
            }
        }
        return request
    }

    /// URLSession getter that handles mTLS and SSL pinning if needed.
    ///
    /// A user-provided session (see `Harbor.setCustomURLSession`) is used as-is. Otherwise a new
    /// session is built per request from the current configuration, so changes to cache type,
    /// timeout, mTLS or SSL pinning always take effect.
    static func getURLSession(for request: any HRequestBaseRequestProtocol) -> URLSession {
        if let customURLSession = HConfig.shared.customURLSession {
            return customURLSession
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = request.timeoutInterval ?? HConfig.shared.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval ?? HConfig.shared.timeoutInterval

        // Only HGetRequestProtocol has cache. For cache types other than .urlCache, install an
        // isolated zero-capacity URLCache so responses are never served from — nor stored
        // into — URLCache.shared.
        if let getRequest = request as? any HGetRequestProtocol {
            let cacheType: HCache.CacheType = getRequest.cacheType ?? HConfig.shared.cacheType

            switch cacheType {
            case .urlCache(let cache, let requestPolicy):
                configuration.urlCache = cache
                configuration.requestCachePolicy = requestPolicy
            case .custom, .disabled:
                configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
            }
        }

        // If mTLS or SSL pinning is configured, create a new URLSession with delegate
        if HConfig.shared.mTLSIdentity != nil || HConfig.shared.sslPinningKeys != nil {
            let sessionDelegate = HURLSessionDelegate(mTLSIdentity: HConfig.shared.mTLSIdentity,
                                                      sslPinningKeys: HConfig.shared.sslPinningKeys)
            return URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
        }

        return URLSession(configuration: configuration)
    }

    /// Builds the URL used for synthetic mock responses.
    private static func mockURL(for request: any HRequestBaseRequestProtocol) -> URL {
        if let getRequest = request as? any HGetRequestProtocol,
           let url = HURLBuilder.compositeURL(url: getRequest.url, pathParameters: getRequest.pathParameters, queryParameters: getRequest.queryParameters) {
            return url
        }
        return HURLBuilder.compositeURL(url: request.url, pathParameters: request.pathParameters) ?? URL(fileURLWithPath: "/")
    }

    static func logError(_ error: HRequestError, request: HRequestBaseRequestProtocol) {
        if let request = request as? HDebugRequestProtocol {
            request.logErrorResponse(error: error)
        }
    }
}

// MARK: - Auth Validation Functions
private extension HRequestManager {
    // This method checks that the used authorization headers is an old one
    static func hasNewAuthorizationHeader(request: HRequestBaseRequestProtocol) async -> Bool {
        guard let headerParameters = request.headerParameters,
              let currentAuthorizationHeader = await HConfig.shared.authProvider?.getAuthorizationHeader(),
              let usedAuthorization = headerParameters[currentAuthorizationHeader.key]
        else { return false }

        let currentAuthorization = currentAuthorizationHeader.value

        if usedAuthorization != currentAuthorization {
            return true
        }

        return false
    }
}
