//
//  HRequestManager.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import SystemConfiguration

/// Actor to manage shared mutable state in a thread-safe way
@globalActor public actor HRequestManagerActor {
    public static let shared = HRequestManagerActor()
}

@HRequestManagerActor
internal final class HRequestManager: Sendable {
    internal static var config: HConfig = HConfig()
}

// MARK: - Request With Result
extension HRequestManager {

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

    static func request<Model: Codable>(model: Model.Type, request: any HRequestWithResultProtocol) async -> HResponseWithResult<Model> {
        if !self.isConnectedToNetwork() {
            return .error(.noConnectionError)
        }

        guard let modifiedRequest = await addAuthCredentialsIfNeeded(request) as? (any HRequestWithResultProtocol) else { return .error(.authProviderNeeded) }

        let result = await requestHandler(model: model, request: modifiedRequest)
        return result
    }

    private static func requestHandler<Model: Codable>(model: Model.Type, request: any HRequestWithResultProtocol) async -> HResponseWithResult<Model> {
        guard let urlRequest = self.buildUrlRequest(request: request) else {
            return .error(.malformedRequestError)
        }

        if let request = request as? HDebugRequestProtocol {
            request.printRequest(urlRequest: urlRequest)
        }

        do {

            let session = getSession()

            let startTime = Date()

            let (data, httpResponse) = try await session.data(for: urlRequest)

            let duration = Date().timeIntervalSince(startTime) * 1000

            guard let httpResponse = httpResponse as? HTTPURLResponse else {
                if let retries = request.retries, retries > 0 {
                    var mutableRequest = request
                    mutableRequest.retries = retries - 1
                    return await self.request(model: model, request: mutableRequest)
                } else {
                    return .error(.invalidHttpResponse)
                }
            }

            if let request = request as? HDebugRequestProtocol {
                request.printResponse(httpResponse: httpResponse, data: data, duration: duration)
            }

            switch httpResponse.statusCode {
            case 200 ... 299:
                do {
                    let parsedResponse = try request.parseData(data: data, model: model)
                    return .success(parsedResponse)
                } catch let parseError {
                    return .error(.codableError(modelName: "\(model.self)", error: parseError))
                }
            case 401:
                if await !hasNewAuthorizationHeader(request: request) {
                    await Self.config.authProvider?.authFailed()
                    return .error(.authNeeded)
                } else {
                    return await self.request(model: model, request: request)
                }
            default:
                if let retries = request.retries, retries > 0 {
                    var mutableRequest = request
                    mutableRequest.retries = retries - 1
                    return await self.request(model: model, request: mutableRequest)
                } else {
                    return .error(.apiError(statusCode: httpResponse.statusCode, data: data))
                }
            }
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                return .cancelled
            case .badURL, .cannotConnectToHost, .serverCertificateUntrusted:
                return .error(.malformedRequestError)
            case .timedOut:
                return .error(.timeoutError)
            case .notConnectedToInternet, .networkConnectionLost:
                return .error(.noConnectionError)
            default:
                return .error(.invalidHttpResponse)
            }
        } catch {
            return .error(.invalidHttpResponse)
        }
    }
}

// MARK: - Request Without Result
extension HRequestManager {
    static func request(request: any HRequestWithEmptyResponseProtocol) async -> HResponse {
        if !self.isConnectedToNetwork() {
            return .error(.noConnectionError)
        }

        guard let modifiedRequest = await addAuthCredentialsIfNeeded(request) as? (any HRequestWithEmptyResponseProtocol) else { return .error(.authProviderNeeded) }

        let result = await requestHandler(request: modifiedRequest)
        return result
    }

    private static func requestHandler<P: HRequestWithEmptyResponseProtocol>(request: P) async -> HResponse {
        guard let urlRequest = self.buildUrlRequest(request: request) else {
            return .error(.malformedRequestError)
        }

        if let request = request as? HDebugRequestProtocol {
            request.printRequest(urlRequest: urlRequest)
        }

        do {

            let session = getSession()

            let startTime = Date()

            let (data, httpResponse) = try await session.data(for: urlRequest)

            let duration = Date().timeIntervalSince(startTime) * 1000

            guard let httpResponse = httpResponse as? HTTPURLResponse else {
                if let retries = request.retries, retries > 0 {
                    var mutableRequest = request
                    mutableRequest.retries = retries - 1
                    return await self.request(request: mutableRequest)
                } else {
                    return .error(.invalidHttpResponse)
                }
            }

            if let request = request as? HDebugRequestProtocol {
                request.printResponse(httpResponse: httpResponse, data: data, duration: duration)
            }

            switch httpResponse.statusCode {
            case 200 ... 299:
                return .success
            case 401:
                if await !hasNewAuthorizationHeader(request: request) {
                    await Self.config.authProvider?.authFailed()
                    return .error(.authNeeded)
                } else {
                    return await self.request(request: request)
                }
            default:
                if let retries = request.retries, retries > 0 {
                    var mutableRequest = request
                    mutableRequest.retries = retries - 1
                    return await self.request(request: mutableRequest)
                } else {
                    return .error(.apiError(statusCode: httpResponse.statusCode, data: data))
                }
            }
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                return .cancelled
            case .badURL, .cannotConnectToHost, .serverCertificateUntrusted:
                return .error(.malformedRequestError)
            case .timedOut:
                return .error(.timeoutError)
            case .notConnectedToInternet, .networkConnectionLost:
                return .error(.noConnectionError)
            default:
                return .error(.invalidHttpResponse)
            }
        } catch {
            return .error(.invalidHttpResponse)
        }
    }
}

// MARK: - Request Builder Functions
internal extension HRequestManager {
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

    /// Session getter that handles mTLS and SSL pinning if needed
    private static func getSession() -> URLSession {
        if let currentSession = config.currentSession {
            return currentSession
        }

        // If mTLS or SSL pinning is configured, create a new session with delegate
        if config.mTLS != nil || config.sslPinningSHA256 != nil {
            let sessionDelegate = HURLSessionDelegate(mTLS: config.mTLS, sslPinningSHA256: config.sslPinningSHA256)
            let newSession = URLSession(configuration: .default, delegate: sessionDelegate, delegateQueue: nil)
            config.currentSession = newSession
            return newSession
        }

        // Otherwise use the default shared session
        return config.defaultSession
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
