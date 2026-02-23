//
//  HRequestManager.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import Network

/// Global actor to manage shared mutable state in a thread-safe way.
/// This actor ensures that Harbor's internal state is accessed safely across concurrent contexts.
@globalActor public actor HRequestManagerActor {
    /// The shared instance of the actor.
    public static let shared = HRequestManagerActor()
}

@HRequestManagerActor
final class HRequestManager: Sendable {}

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
            return await HRequestManager.processResponse(model: model, request: request, statusCode: mock.statusCode, data: data)
        }

        if !self.isConnectedToNetwork() {
            let hError: HRequestError = .noConnectionError
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
        guard let urlRequest = HURLBuilder.buildUrlRequest(request: request) else {
            let hError: HRequestError = .malformedRequestError
            logError(hError, request: request)
            return .error(hError)
        }

        if let request = request as? HDebugRequestProtocol {
            request.logRequest(urlRequest: urlRequest)
        }

        do {
            let session = getURLSession(for: request)

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
            let hError: HRequestError
            switch error.code {
            case .cancelled:
                hError = .cancelled
            case .badURL:
                hError = .malformedRequestError
            case .cannotConnectToHost, .serverCertificateUntrusted:
                hError = .cannotFindHost
            case .timedOut:
                hError = .timeoutError
            case .notConnectedToInternet, .networkConnectionLost:
                hError = .noConnectionError
            case .cannotFindHost:
                hError = .cannotFindHost
            default:
                hError = .invalidHttpResponse
            }
            logError(hError, request: request)
            return .error(hError)
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
                let hError: HRequestError = .codableError(modelName: "\(model.self)", error: parseError)
                logError(hError, request: request)
                return .error(hError)
            }
        case 304:
            // Not Modified — return cached data from custom cache.
            // (URLCache handles 304 transparently at URLSession level; this branch handles custom cache.)
            if let getRequest = request as? any HGetRequestProtocol,
               let cachedAny = await getRequest.cache(),
               let cachedModel = cachedAny as? Model {
                return .success(cachedModel)
            } else {
                let hError: HRequestError = .apiError(statusCode: statusCode, data: data)
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
                let hError: HRequestError = .apiError(statusCode: statusCode, data: data)
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

        if !self.isConnectedToNetwork() {
            let hError: HRequestError = .noConnectionError
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
        guard let urlRequest = HURLBuilder.buildUrlRequest(request: request) else {
            let hError: HRequestError = .malformedRequestError
            logError(hError, request: request)
            return .error(hError)
        }

        if let request = request as? HDebugRequestProtocol {
            request.logRequest(urlRequest: urlRequest)
        }

        do {
            let session = getURLSession(for: request)

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
            let hError: HRequestError
            switch error.code {
            case .cancelled:
                hError = .cancelled
            case .badURL:
                hError = .malformedRequestError
            case .cannotConnectToHost, .serverCertificateUntrusted:
                hError = .cannotFindHost
            case .timedOut:
                hError = .timeoutError
            case .notConnectedToInternet, .networkConnectionLost:
                hError = .noConnectionError
            case .cannotFindHost:
                hError = .cannotFindHost
            default:
                hError = .invalidHttpResponse
            }
            logError(hError, request: request)
            return .error(hError)
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
                let hError: HRequestError = .apiError(statusCode: statusCode, data: data)
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

    /// URLSession getter that handles mTLS and SSL pinning if needed
    /// Returns a cached session or creates a new optimized one
    static func getURLSession(for request: any HRequestBaseRequestProtocol) -> URLSession {
        // Return cached session if available and configuration hasn't changed
        if let currentURLSession = HConfig.shared.currentURLSession {
            return currentURLSession
        }

        let configuration = URLSessionConfiguration.default
        // TODO: Implement request config timeout
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        
        // Resolve effective cache type: request-specific takes precedence over global default
        // Only HGetRequestProtocol has cache
        if let getRequest = request as? any HGetRequestProtocol {
            let cacheType: HCache.CacheType = getRequest.cacheType ?? HConfig.shared.defaultCacheType

            if case .urlCache(let cache, let requestPolicy) = cacheType {
                configuration.urlCache = cache
                configuration.requestCachePolicy = requestPolicy
            }
        }

        // If mTLS or SSL pinning is configured, create a new URLSession with delegate
        if HConfig.shared.mTLSIdentity != nil || HConfig.shared.sslPinningKeys != nil {
            let sessionDelegate = HURLSessionDelegate(mTLSIdentity: HConfig.shared.mTLSIdentity,
                                                      sslPinningKeys: HConfig.shared.sslPinningKeys)
            let newSession = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
            HConfig.shared.currentURLSession = newSession
            return newSession
        }

        // Create session without delegate for standard requests
        let newSession = URLSession(configuration: configuration)
        HConfig.shared.currentURLSession = newSession
        return newSession
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

// MARK: - Connectivity Functions
private extension HRequestManager {
    private static let monitor = NWPathMonitor()
    private static let monitorQueue = DispatchQueue(label: "com.harbor.networkMonitor")
    private static var isMonitorStarted = false

    /// Enhanced network connectivity check using NWPathMonitor
    static func isConnectedToNetwork() -> Bool {
        if !isMonitorStarted {
            monitor.start(queue: monitorQueue)
            isMonitorStarted = true
        }

        if monitor.currentPath.status == .satisfied {
            return true
        }

        // Fallback for debug/simulator environments
        #if DEBUG || targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}
