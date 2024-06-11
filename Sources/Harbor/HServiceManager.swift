//
//  HServiceManager.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import SystemConfiguration

internal final class HServiceManager {
    
    // TODO: Move to a config class
    internal static var authProvider: HAuthProviderProtocol?
    internal static var defaultHeaderParameters: [String: String]?
}

// MARK: - Request With Result
extension HServiceManager {
    static func request<T: Codable, P: HServiceResultRequestProtocol>(model: T.Type, service: P) async -> HResponseWithResult<T> {
        if !self.isConnectedToNetwork() {
            return .error(.noConnectionError)
        }

        if service.needsAuth {
            if let authCredential = await authProvider?.getAuthorizationHeader() {
                if service.headerParameters == nil {
                    service.headerParameters = [String: String]()
                }

                service.headerParameters?[authCredential.key] = authCredential.value

                async let result = self.requestHandler(model: model, service: service)
                return await result
            } else {
                return .error(.authProviderNeeded)
            }
        } else {
            async let result = self.requestHandler(model: model, service: service)
            return await result
        }
    }

    private static func requestHandler<T: Codable, P: HServiceResultRequestProtocol>(model: T.Type, service: P) async -> HResponseWithResult<T> {
        guard let urlRequest = self.buildRequest(service: service) else {
            return .error(.malformedRequestError)
        }

        if let service = service as? HDebugRequestProtocol {
            service.printRequest(request: urlRequest)
        }

        do {
            let startTime = Date()

            let (data, httpResponse) = try await URLSession.shared.data(for: urlRequest)

            let duration = Date().timeIntervalSince(startTime) * 1000

            guard let httpResponse = httpResponse as? HTTPURLResponse else {
                return .error(.invalidHttpResponse)
            }

            if let service = service as? HDebugRequestProtocol {
                service.printResponse(httpResponse: httpResponse, data: data, duration: duration)
            }

            switch httpResponse.statusCode {
            case 200 ... 299:
                if let parsedResponse = service.parseData(data: data, model: model) {
                    return .success(parsedResponse)
                } else {
                    return .error(.codableError)
                }
            case 401:
                if await !hasNewAuthorizationHeader(service: service) {
                    Self.authProvider?.authFailed()
                }
                return .error(.authNeeded)
            default:
                return .error(.apiError(statusCode: httpResponse.statusCode, data: data))
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
        } catch let error {
            return .error(.invalidHttpResponse)
        }
    }
}

// MARK: - Request Without Result
extension HServiceManager {
    static func request<P: HServiceEmptyResponseProtocol>(service: P) async -> HResponse {
        if !self.isConnectedToNetwork() {
            return .error(.noConnectionError)
        }

        if service.needsAuth {
            if let authCredential = await authProvider?.getAuthorizationHeader() {
                if service.headerParameters == nil {
                    service.headerParameters = [String: String]()
                }

                service.headerParameters?[authCredential.key] = authCredential.value

                async let result = self.requestHandler(service: service)
                return await result
            } else {
                return .error(.authProviderNeeded)
            }
        } else {
            async let result = self.requestHandler(service: service)
            return await result
        }
    }

    private static func requestHandler<P: HServiceEmptyResponseProtocol>(service: P) async -> HResponse {
        guard let urlRequest = self.buildRequest(service: service) else {
            return .error(.malformedRequestError)
        }

        if let service = service as? HDebugRequestProtocol {
            service.printRequest(request: urlRequest)
        }

        do {
            let startTime = Date()

            let (data, httpResponse) = try await URLSession.shared.data(for: urlRequest)

            let duration = Date().timeIntervalSince(startTime) * 1000

            guard let httpResponse = httpResponse as? HTTPURLResponse else {
                return .error(.invalidHttpResponse)
            }

            if let service = service as? HDebugRequestProtocol {
                service.printResponse(httpResponse: httpResponse, data: data, duration: duration)
            }

            switch httpResponse.statusCode {
            case 200 ... 299:
                return .success
            case 401:
                if await !hasNewAuthorizationHeader(service: service) {
                    Self.authProvider?.authFailed()
                }
                return .error(.authNeeded)
            default:
                return .error(.apiError(statusCode: httpResponse.statusCode, data: data))
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
        } catch let error {
            return .error(.invalidHttpResponse)
        }
    }
}

// MARK: - Request Builder Functions
private extension HServiceManager {
    static func buildRequest<P: HServiceBaseRequestProtocol>(service: P) -> URLRequest? {
        let url: URL?

        switch service.httpMethod {
        case .get:
            guard let service = service as? (any HServiceGetRequestProtocol) else { return nil }
            url = compositeURL(url: service.url, pathParameters: service.pathParameters, queryParameters: service.queryParameters)
        case .post, .put, .patch, .delete:
            url = compositeURL(url: service.url, pathParameters: service.pathParameters)
        }

        guard let url else { return nil }

        var request = URLRequest(url: url)

        request.allHTTPHeaderFields = getHeaderParameters(serviceHeaderParameters: service.headerParameters)
        request.httpMethod = service.httpMethod.rawValue
        // TODO: Move to a config class
        request.httpShouldHandleCookies = false

        if let service = service as? HServiceBodyRequestProtocol, let parameters = service.bodyParameters {
            switch service.bodyType {
            case .json:
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = dataBody(params: parameters, type: .json, boundary: nil)
            case .multipart:
                let boundary = "Boundary-\(UUID().uuidString)"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                request.httpBody = dataBody(params: parameters, type: .multipart, boundary: boundary)
            }
        }

        return request
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

    static func dataBody(params: [String: Any], type: HServiceRequestDataType, boundary: String? = nil) -> Data? {
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

    static func getHeaderParameters(serviceHeaderParameters: [String: String]? = nil) -> [String: String] {
        var headers: [String: String] = defaultHeaderParameters ?? [String: String]()

        if let serviceHeaderParameters, !serviceHeaderParameters.isEmpty {
            headers.merge(serviceHeaderParameters, uniquingKeysWith: { (_, new) in new })
        }

        return headers
    }
}

// MARK: - Auth Validation Functions
private extension HServiceManager {
    // This method checks that the used authorization headers is an old one
    static func hasNewAuthorizationHeader(service: HServiceBaseRequestProtocol) async -> Bool {
        guard let headerParameters = service.headerParameters,
              let currentAuthorizationHeader = await authProvider?.getAuthorizationHeader(),
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
private extension HServiceManager {
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
