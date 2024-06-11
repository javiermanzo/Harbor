//
//  HDebugRequestProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

public protocol HDebugRequestProtocol: AnyObject {
    var debugType: HDebugRequestType { get set }
}

public enum HDebugRequestType {
    case none
    case request
    case response
    case requestAndResponse
}

public extension HDebugRequestProtocol {
    func printResponse(httpResponse: HTTPURLResponse, data: Data, duration: Double) {
        if self.debugType == .response || self.debugType == .requestAndResponse {
            let responseData: String = String(data: data, encoding: String.Encoding.ascii) ?? "<uknown>"
            print("📎------------------------------------------------------------------------------📎")
            print("-----------------------------------RESPONSE---------------------------------------")
            print("🌐 Request: " + String(describing: self) + "<" + String(describing: ObjectIdentifier(self)) + ">" + "\n" +
                  "ℹ️ Response: " + httpResponse.debugDescription + "\n" +
                  "⌛️ Response time: \(String(format: "%.2f", duration))ms \n" +
                  "🏋️ Data size: " + data.debugDescription + "\n" +
                  "📄 Data value: " + responseData)
            print("📎------------------------------------------------------------------------------📎")
        }
    }
    
    func printRequest(urlRequest: URLRequest) {
        if let request = self as? HRequestBaseRequestProtocol,
           self.debugType == .request || self.debugType == .requestAndResponse {
            var info: String = "{\n\tneedsAuth: " + String(describing: request.needsAuth) +
            "\n\turl: " + String(describing: urlRequest.url) +
            "\n\thttpMethod: " + String(describing: request.httpMethod) +
            "\n\theaders: " + String(describing: request.headerParameters) +
            "\n\tpathParameters: " + String(describing: request.pathParameters)

            if let s = self as? (any HGetRequestProtocol) {
                info += "\n\tqueryParameters: " + String(describing: s.queryParameters)
            }
            
            if let s = self as? HRequestWithBodyProtocol {
                info += "\n\tbody: " + String(describing: s.bodyParameters)
            }
            
            info += "\n}"
            
            let curl = self.generateCurl(urlRequest: urlRequest)

            print("📎------------------------------------------------------------------------------📎")
            print("------------------------------------REQUEST---------------------------------------")
            print("🌐 Request:" + String(describing: request) + "<" + String(describing: ObjectIdentifier(self)) + ">" + "\n" +
                  "ℹ️ Details: " + info + "\n" +
                  "🏃‍♂️ curl: " + curl)
            print("📎------------------------------------------------------------------------------📎")
        }
    }
    
    private func generateCurl(urlRequest: URLRequest) -> String {
        var components = ["$ curl -v"]
        
        guard let url = urlRequest.url,
              let /*host*/_ = url.host
        else {
            return "$ curl command could not be created"
        }
        
        if let httpMethod = urlRequest.httpMethod, httpMethod != "GET" {
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
        
        urlRequest.allHTTPHeaderFields?.filter { $0.0 != "Cookie" }
            .forEach { headers[$0.0] = $0.1 }
        
        components += headers.map {
            let escapedValue = String(describing: $0.value).replacingOccurrences(of: "\"", with: "\\\"")
            
            return "-H \"\($0.key): \(escapedValue)\""
        }
        
        if let httpBodyData = urlRequest.httpBody, let httpBody = String(data: httpBodyData, encoding: .utf8) {
            var escapedBody = httpBody.replacingOccurrences(of: "\\\"", with: "\\\\\"")
            escapedBody = escapedBody.replacingOccurrences(of: "\"", with: "\\\"")
            
            components.append("-d \"\(escapedBody)\"")
        }
        
        components.append("\"\(url.absoluteString)\"")
        
        return components.joined(separator: " \\\n\t")
    }
}
