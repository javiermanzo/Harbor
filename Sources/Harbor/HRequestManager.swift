//
//  HRequestManager.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import SystemConfiguration
import LogBird

/// Actor to manage shared mutable state in a thread-safe way
@globalActor public actor HRequestManagerActor {
    public static let shared = HRequestManagerActor()
}

@HRequestManagerActor
final class HRequestManager: Sendable {
    static var config: HConfig = HConfig()

    static let logger = LogBird(subsystem: "com.harbor", category: "debugging")
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

            return await processResponse(model: model, request: request, statusCode: httpResponse.statusCode, data: data)
        } catch let error as URLError {
            let hError: HRequestError
            switch error.code {
            case .cancelled:
                hError = .cancelled
            case .badURL, .cannotConnectToHost, .serverCertificateUntrusted:
                hError = .malformedRequestError
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

    static func processResponse<Model: HModel>(model: Model.Type, request: any HRequestWithResultProtocol, statusCode: Int, data: Data) async -> HResponseWithResult<Model> {
        switch statusCode {
        case 200 ... 299:
            do {
                let parsedResponse = try request.parseData(data: data, model: model)
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
            case .badURL, .cannotConnectToHost, .serverCertificateUntrusted:
                hError = .malformedRequestError
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
            url = compositeURL(url: request.url, pathParameters: request.pathParameters, queryParameters: request.queryParameters)
        case .post, .put, .patch, .delete:
            url = compositeURL(url: request.url, pathParameters: request.pathParameters)
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

    static func compositeURL(url: String, pathParameters: [String: String]? = nil, queryParameters: [String: String]? = nil) -> URL? {
        var compositeUrl = url

        if let pathParameters {
            for (key, value) in pathParameters {
                compositeUrl = compositeUrl.replacingOccurrences(of: "{\(key)}", with: value)
            }
        }

        var url: URL? = URL(string: compositeUrl)

        if var urlComponents = URLComponents(string: compositeUrl), let queryParameters, !queryParameters.isEmpty {
            var queryItems = [URLQueryItem]()

            for (key, value) in queryParameters {
                queryItems.append(URLQueryItem(name: key, value: value))
            }

            queryItems.sort(by: { $0.name < $1.name })

            urlComponents.queryItems = queryItems
            url = urlComponents.url
        }

        return url
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
    static func getURLSession() -> URLSession {
        if let currentURLSession = config.currentURLSession {
            return currentURLSession
        }

        // If mTLS or SSL pinning is configured, create a new URLSession with delegate
        if config.mTLS != nil || config.sslPinningSHA256 != nil {
            let sessionDelegate = HURLSessionDelegate(mTLS: config.mTLS, sslPinningSHA256: config.sslPinningSHA256)
            let newSession = URLSession(configuration: .default, delegate: sessionDelegate, delegateQueue: nil)
            config.currentURLSession = newSession
            return newSession
        }

        // Otherwise use the default shared URLSession
        return URLSession.shared
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
    static func isConnectedToNetwork() -> Bool {
        var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)

        let defaultRouteReachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }

        var flags: SCNetworkReachabilityFlags = SCNetworkReachabilityFlags(rawValue: 0)
        if SCNetworkReachabilityGetFlags(defaultRouteReachability!, &flags) == false {
            return false
        }

        // Working for Cellular and WIFI
        let isReachable = (flags.rawValue & UInt32(kSCNetworkFlagsReachable)) != 0
        let needsConnection = (flags.rawValue & UInt32(kSCNetworkFlagsConnectionRequired)) != 0
        let ret = (isReachable && !needsConnection)

        return ret
    }
}
