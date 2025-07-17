//
//  HRequestManager.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import LogBird
import SystemConfiguration

/// Global actor to manage shared mutable state in a thread-safe way.
/// This actor ensures that Harbor's internal state is accessed safely across concurrent contexts.
@globalActor public actor HRequestManagerActor {
    /// The shared instance of the actor.
    public static let shared = HRequestManagerActor()
}

@HRequestManagerActor
final class HRequestManager: Sendable {
    static var config: HConfig = HConfig()
}

// MARK: - Request With Result
extension HRequestManager {
    static func request<Model: HModel>(model: Model.Type, request: any HRequestWithResultProtocol) async -> HResponseWithResult<Model> {
        if let mock = HMocker.mock(request: request), config.mocksEnabled {
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
        guard let urlRequest = self.buildUrlRequest(request: request) else {
            let hError: HRequestError = .malformedRequestError
            logError(hError, request: request)
            return .error(hError)
        }

        if let request = request as? HDebugRequestProtocol {
            request.printRequest(urlRequest: urlRequest)
        }

        do {
            let session = getURLSession()

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
                request.printResponse(httpResponse: httpResponse, data: data, duration: duration)
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
                    await HCache.Manager.shared.storeData(data, for: request, response: httpResponse)
                }

                return .success(parsedResponse)
            } catch let parseError {
                let hError: HRequestError = .codableError(modelName: "\(model.self)", error: parseError)
                logError(hError, request: request)
                return .error(hError)
            }
        case 401:
            if await !hasNewAuthorizationHeader(request: request) {
                await Self.config.authProvider?.authFailed()
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
        if let mock = HMocker.mock(request: request), config.mocksEnabled {
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
        guard let urlRequest = self.buildUrlRequest(request: request) else {
            let hError: HRequestError = .malformedRequestError
            logError(hError, request: request)
            return .error(hError)
        }

        if let request = request as? HDebugRequestProtocol {
            request.printRequest(urlRequest: urlRequest)
        }

        do {
            let session = getURLSession()

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
                request.printResponse(httpResponse: httpResponse, data: data, duration: duration)
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
                await Self.config.authProvider?.authFailed()
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
    static func buildUrlRequest<P: HRequestBaseRequestProtocol>(request: P) -> URLRequest? {
        let url: URL?

        switch request.httpMethod {
        case .get:
            guard let request = request as? (any HGetRequestProtocol) else { return nil }
            url = HURLBuilder.compositeURL(url: request.url, pathParameters: request.pathParameters, queryParameters: request.queryParameters)
        case .post, .put, .patch, .delete:
            url = HURLBuilder.compositeURL(url: request.url, pathParameters: request.pathParameters)
        }

        guard let url else { return nil }

        var urlRequest = URLRequest(url: url)

        urlRequest.httpMethod = request.httpMethod.rawValue
        // TODO: Move to a config class
        urlRequest.httpShouldHandleCookies = false

        if let request = request as? HRequestWithBodyProtocol, let parameters = request.bodyParameters {
            switch request.bodyType {
            case .json:
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = dataBody(params: parameters, type: .json, boundary: nil)
            case .multipart:
                let boundary = "Boundary-\(UUID().uuidString)"
                urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = dataBody(params: parameters, type: .multipart, boundary: boundary)
            }
        }

        if let defaultHeaders = Self.config.defaultHeaderParameters {
            urlRequest.allHTTPHeaderFields = mergeHeaderParameters(currentHeaders: urlRequest.allHTTPHeaderFields, newHeaders: defaultHeaders)
        }

        if let requestHeaderParameters = request.headerParameters {
            urlRequest.allHTTPHeaderFields = mergeHeaderParameters(currentHeaders: urlRequest.allHTTPHeaderFields, newHeaders: requestHeaderParameters)
        }

        return urlRequest
    }


    static func dataBody(params: [String: Any], type: HRequestDataType, boundary: String? = nil) -> Data? {
        if type == .multipart, let boundary {
            return handleFormData(with: params, boundary: boundary)
        }

        do {
            return try JSONSerialization.data(withJSONObject: params, options: .prettyPrinted)
        } catch {
            return nil
        }
    }

    static func handleFormData(with params: [String: Any], boundary: String) -> Data? {
        let httpBody = NSMutableData()
        for (key, value) in params {
            guard let value = value as? String else {
                return nil
            }

            httpBody.appendString(convertFormField(named: key, value: value, using: boundary))
        }

        httpBody.appendString("--\(boundary)--")
        return httpBody as Data
    }

    static func convertFormField(named name: String, value: String, using boundary: String) -> String {
        var fieldString = "--\(boundary)\r\n"
        fieldString += "Content-Disposition: form-data; name=\"\(name)\"\r\n"
        fieldString += "\r\n"
        fieldString += "\(value)\r\n"
        return fieldString
    }

    static func mergeHeaderParameters(currentHeaders: [String: String]?, newHeaders: [String: String]) -> [String: String] {
        if let currentHeaders {
            var headers: [String: String] = currentHeaders

            if !newHeaders.isEmpty {
                headers.merge(newHeaders, uniquingKeysWith: { (_, new) in new })
            }
            return headers
        } else {
            return newHeaders
        }
    }

    static func addAuthCredentialsIfNeeded(_ request: any HRequestBaseRequestProtocol) async -> (any HRequestBaseRequestProtocol)? {
        if request.needsAuth {
            var modifiedRequest = request
            if let authCredential = await Self.config.authProvider?.getAuthorizationHeader() {
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
    static func getURLSession() -> URLSession {
        // Return cached session if available and configuration hasn't changed
        if let currentURLSession = config.currentURLSession {
            return currentURLSession
        }

        let configuration = URLSessionConfiguration.default
        configuration.urlCache = HCache.Manager.shared.currentURLSessionCache
        configuration.requestCachePolicy = .useProtocolCachePolicy

        // TODO: Implement request config timeout
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30

        // If mTLS or SSL pinning is configured, create a new URLSession with delegate
        if config.mTLS != nil || config.sslPinningSHA256 != nil {
            let sessionDelegate = HURLSessionDelegate(mTLS: config.mTLS, sslPinningSHA256: config.sslPinningSHA256)
            let newSession = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
            config.currentURLSession = newSession
            return newSession
        }

        // Create session without delegate for standard requests
        let newSession = URLSession(configuration: configuration)
        config.currentURLSession = newSession
        return newSession
    }

    static func logError(_ error: HRequestError, request: HRequestBaseRequestProtocol) {
        if let request = request as? HDebugRequestProtocol {
            request.printErrorResponse(error: error)
        }
    }
}

// MARK: - Auth Validation Functions
private extension HRequestManager {
    // This method checks that the used authorization headers is an old one
    static func hasNewAuthorizationHeader(request: HRequestBaseRequestProtocol) async -> Bool {
        guard let headerParameters = request.headerParameters,
              let currentAuthorizationHeader = await Self.config.authProvider?.getAuthorizationHeader(),
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
    /// Enhanced network connectivity check with fallback strategies
    static func isConnectedToNetwork() -> Bool {
        // Primary check: SystemConfiguration reachability
        if let reachability = createReachabilityRef() {
            var flags: SCNetworkReachabilityFlags = SCNetworkReachabilityFlags(rawValue: 0)
            
            guard SCNetworkReachabilityGetFlags(reachability, &flags) else {
                return performFallbackConnectivityCheck()
            }
            
            let isReachable = flags.contains(.reachable)
            let needsConnection = flags.contains(.connectionRequired)
            let isWWAN = flags.contains(.isWWAN)
            
            // Connected if reachable and doesn't need connection, or if on cellular
            if isReachable && (!needsConnection || isWWAN) {
                return true
            }
        }
        
        // Fallback connectivity check
        return performFallbackConnectivityCheck()
    }
    
    /// Creates a reachability reference for network status checking
    private static func createReachabilityRef() -> SCNetworkReachability? {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        return withUnsafePointer(to: &zeroAddress) { zeroSockAddress in
            zeroSockAddress.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                SCNetworkReachabilityCreateWithAddress(nil, sockAddr)
            }
        }
    }
    
    /// Fallback connectivity check for edge cases
    private static func performFallbackConnectivityCheck() -> Bool {
        // In debug/simulator environments, be more lenient
        #if DEBUG || targetEnvironment(simulator)
        return true
        #else
        // For release builds, assume no connection if primary check fails
        return false
        #endif
    }
}
