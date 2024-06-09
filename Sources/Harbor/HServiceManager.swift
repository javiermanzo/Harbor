//
//  HServiceManager.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import SystemConfiguration

internal final class HServiceManager {

    internal static var authProvider: HAuthProviderProtocol?

    // MARK: -  Request With Result
    static func request<T: Codable, P: HServiceProtocolWithResult>(model: T.Type, service: P) async -> HResponseWithResult<T> {
        if !self.isConnectedToNetwork() {
            return .error(.noConnectionError)
        }
        
        if service.needAuth {
            if let authProvider = Self.authProvider {
                if service.headers == nil {
                    service.headers = [String: String]()
                }
                
                service.headers?.merge(await authProvider.getCredentialsHeader(), uniquingKeysWith: { (_, new) in new })
                
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
    
    private static func requestHandler<T: Codable, P: HServiceProtocolWithResult>(model: T.Type, service: P) async -> HResponseWithResult<T> {
        guard let request = self.buildRequest(service: service) else {
            return .error(.malformedRequestError)
        }
        
        if let service = service as? HDebugServiceProtocol {
            service.printRequest(request: request)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .error(.invalidHttpResponse)
            }
            
            if let service = service as? HDebugServiceProtocol {
                service.printResponse(httpResponse: httpResponse, data: data)
            }
            
            switch httpResponse.statusCode {
            case 200 ... 299:
                if let parsedResponse = service.parseData(data: data, model: model) {
                    return .success(parsedResponse)
                } else {
                    return .error(.codableError)
                }
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
    
    // MARK: -  Request Without Result
    static func request<P: HServiceProtocol>(service: P) async -> HResponse {
        if !self.isConnectedToNetwork() {
            return .error(.noConnectionError)
        }
        
        if service.needAuth {
            if let authProvider = Self.authProvider {
                if service.headers == nil {
                    service.headers = [String: String]()
                }
                
                service.headers?.merge(await authProvider.getCredentialsHeader(), uniquingKeysWith: { (_, new) in new })
                
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
    
    private static func requestHandler<P: HServiceProtocol>(service: P) async -> HResponse {
        guard let request = self.buildRequest(service: service) else {
            return .error(.malformedRequestError)
        }
        
        if let service = service as? HDebugServiceProtocol {
            service.printRequest(request: request)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .error(.invalidRequest)
            }
            
            if let service = service as? HDebugServiceProtocol {
                service.printResponse(httpResponse: httpResponse, data: data)
            }

            switch httpResponse.statusCode {
            case 200 ... 299:
                return .success
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
    
    
    // MARK: -  Private Base Methods
    private static func buildRequest<P: HServiceProtocolBase>(service: P) -> URLRequest? {
        guard let url = compositeURL(url: service.url, pathParams: service.pathParameters, queryParams:  service.queryParameters) else { return nil }
        
        var request = URLRequest(url: url)
        
        if let headers = service.headers, !headers.isEmpty {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        request.httpMethod = service.httpMethod.rawValue
        
        request.timeoutInterval = service.timeout
        
        if let body = service.dataBody() {
            request.httpBody = body
            request.setValue( "\(body.count)", forHTTPHeaderField: "Content-Length")
        }
        
        return request
    }
    
    private static func compositeURL(url: String, pathParams: [String: String]?, queryParams: [String: String]?) -> URL? {
        var compositeUrl = url

        if let pathParams {
            for (key, value) in pathParams {
                compositeUrl = compositeUrl.replacingOccurrences(of: "{\(key)}", with: value)
            }
        }

        var url: URL? = URL(string: compositeUrl)

        if var urlComponents = URLComponents(string: compositeUrl), let queryParams, !queryParams.isEmpty {
            var queryItems = [URLQueryItem]()

            for (key, value) in queryParams {
                queryItems.append(URLQueryItem(name: key, value: value))
            }

            queryItems.sort(by: { $0.name < $1.name })

            urlComponents.queryItems = queryItems
            url = urlComponents.url
        }

        return url
    }
    
    private static func isConnectedToNetwork() -> Bool {
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
