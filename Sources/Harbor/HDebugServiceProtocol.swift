//
//  HDebugServiceProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

public protocol HDebugServiceProtocol: AnyObject {
    var debugType: HDebugServiceType { get set }
}

public enum HDebugServiceType {
    case none
    case request
    case response
    case requestAndResponse
}

public extension HDebugServiceProtocol {
    func printResponse(httpResponse: HTTPURLResponse, data : Data) {
        if self.debugType == .response || self.debugType == .requestAndResponse {
            let responseData:String = String(data: data, encoding: String.Encoding.ascii) ?? "<uknown>"
            print("📎------------------------------------------------------------------------------📎")
            print("-----------------------------------RESPONSE---------------------------------------")
            print("🌐 Service: " + String(describing: self) + "<" + String(describing: ObjectIdentifier(self)) + ">" + "\n" +
                  "ℹ️ Response: " + httpResponse.debugDescription + "\n" +
                  "🏋️ Data size: " + data.debugDescription + "\n" +
                  "📄 Data value: " + responseData)
            print("📎------------------------------------------------------------------------------📎")
        }
    }
    
    func printRequest(request: URLRequest) {
        if let service = self as? HServiceProtocolBase,
           self.debugType == .request || self.debugType == .requestAndResponse {
            let info: String = "{\n\tneedAuth: " + String(describing: service.needAuth) +
            "\n\turl: " + String(describing: request.url) +
            "\n\thttpMethod: " + String(describing: service.httpMethod) +
            "\n\theaderParameters: " + String(describing: service.headerParameters) +
            "\n\tqueryParameters: " + String(describing: service.queryParameters) +
            "\n\tpathParameters: " + String(describing: service.pathParameters) +
            "\n\tbody: " + String(describing: service.body) +
            "\n\ttimeout: " + String(describing: service.timeout) +
            "\n}"
            
            let curl = self.generateCurl(request: request)
            
            print("📎------------------------------------------------------------------------------📎")
            print("------------------------------------REQUEST---------------------------------------")
            print("🌐 Service:" + String(describing: service) + "<" + String(describing: ObjectIdentifier(self)) + ">" + "\n" +
                  "ℹ️ Details: " + info + "\n" +
                  "🏃‍♂️ curl: " + curl)
            print("📎------------------------------------------------------------------------------📎")
        }
    }
    
    private func generateCurl(request: URLRequest) -> String {
        var components = ["$ curl -v"]
        
        guard let url = request.url,
              let /*host*/_ = url.host
        else {
            return "$ curl command could not be created"
        }
        
        if let httpMethod = request.httpMethod, httpMethod != "GET" {
            components.append("-X \(httpMethod)")
        }
        
        if URLSession.shared.configuration.httpShouldSetCookies {
            if let cookieStorage = URLSession.shared.configuration.httpCookieStorage,
               let cookies = cookieStorage.cookies(for: url), !cookies.isEmpty {
                let string = cookies.reduce("") { $0 + "\($1.name)=\($1.value);" }
                components.append("-b \"\(string[..<string.index(before: string.endIndex)])\"")
            }
        }
        
        var headers: [AnyHashable: Any] = [:]
        
        URLSession.shared.configuration.httpAdditionalHeaders?.filter {  $0.0 != AnyHashable("Cookie") }
            .forEach { headers[$0.0] = $0.1 }
        
        request.allHTTPHeaderFields?.filter { $0.0 != "Cookie" }
            .forEach { headers[$0.0] = $0.1 }
        
        components += headers.map {
            let escapedValue = String(describing: $0.value).replacingOccurrences(of: "\"", with: "\\\"")
            
            return "-H \"\($0.key): \(escapedValue)\""
        }
        
        if let httpBodyData = request.httpBody, let httpBody = String(data: httpBodyData, encoding: .utf8) {
            var escapedBody = httpBody.replacingOccurrences(of: "\\\"", with: "\\\\\"")
            escapedBody = escapedBody.replacingOccurrences(of: "\"", with: "\\\"")
            
            components.append("-d \"\(escapedBody)\"")
        }
        
        components.append("\"\(url.absoluteString)\"")
        
        return components.joined(separator: " \\\n\t")
    }
}
