//
//  HDebugRequestProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import LogBird

/// Protocol for adding debug capabilities to network requests.
/// Implement this protocol to enable detailed logging of requests and responses.
public protocol HDebugRequestProtocol {
    /// The type of debug information to log.
    var debugType: HDebugRequestType { get set }
}

/// Specifies the type of debug information to log for network requests.
public enum HDebugRequestType: Sendable {
    /// No debug information is logged.
    case none
    /// Only request information is logged.
    case request
    /// Only response information is logged.
    case response
    /// Both request and response information is logged.
    case requestAndResponse
}

@HRequestManagerActor
public extension HDebugRequestProtocol {
    /// Prints detailed request information to the console.
    /// - Parameter urlRequest: The URL request to debug.
    func printRequest(urlRequest: URLRequest) {
        if let request = self as? HRequestBaseRequestProtocol,
           self.debugType == .request || self.debugType == .requestAndResponse {
            var additionalInfo: [String: String] = [:]
            additionalInfo["request"] = String(describing: type(of: self))
            additionalInfo["url"] = urlRequest.url?.absoluteString
            additionalInfo["httpMethod"] = request.httpMethod.rawValue

            if let headers = dictionaryToJSONString(urlRequest.allHTTPHeaderFields) {
                additionalInfo["headerParameters"] = String(describing: headers)
            }

            if let pathParameters = dictionaryToJSONString(request.pathParameters) {
                additionalInfo["pathParameters"] = String(describing: pathParameters)
            }

            if let r = self as? (any HGetRequestProtocol),
               let queryParameters = dictionaryToJSONString(r.queryParameters) {
                additionalInfo["queryParameters"] = queryParameters
            }

            if let r = self as? (any HRequestWithBodyProtocol),
               let bodyParameters = dictionaryToJSONString(r.bodyParameters) {
                additionalInfo["bodyParameters"] = bodyParameters
            }

            additionalInfo["needsAuth"] = String(describing: request.needsAuth)

            let curl = self.generateCurl(urlRequest: urlRequest)
            let extraMessages: [LBExtraMessage] = [LBExtraMessage(title: "cURL", message: curl)]

            HRequestManager.logger.log("Request \(String(describing: type(of: request)))", extraMessages: extraMessages, additionalInfo: additionalInfo, level: .debug)
        }
    }

    /// Prints detailed response information to the console.
    /// - Parameters:
    ///   - httpResponse: The HTTP response received.
    ///   - data: The response data.
    ///   - duration: The request duration in milliseconds.
    func printResponse(httpResponse: HTTPURLResponse, data: Data, duration: Double) {
        if self.debugType == .response || self.debugType == .requestAndResponse {
            var extraMessages: [LBExtraMessage] = []
            if let value = String(data: data, encoding: String.Encoding.ascii) {
                extraMessages.append(LBExtraMessage(title: "Response Value", message: value))
            }

            extraMessages.append(LBExtraMessage(title: "Response Object", message: httpResponse.debugDescription))

            var additionalInfo: [String: String] = [:]
            additionalInfo["request"] = String(describing: type(of: self))
            additionalInfo["size"] = data.debugDescription
            additionalInfo["duration"] = "\(String(format: "%.2f", duration))ms"

            HRequestManager.logger.log("Response \(String(describing: type(of: self)))", extraMessages: extraMessages, additionalInfo: additionalInfo, level: .debug)
        }
    }

    /// Prints error response information to the console.
    /// - Parameter error: The error that occurred during the request.
    func printErrorResponse(error: HRequestError) {
        if self.debugType == .response || self.debugType == .requestAndResponse {
            var extraMessages: [LBExtraMessage] = []

            extraMessages.append(LBExtraMessage(title: "Error Type", message: "\(error)"))

            var additionalInfo: [String: String] = [:]
            additionalInfo["request"] = String(describing: type(of: self))

            HRequestManager.logger.log("Response Error \(String(describing: type(of: self)))", extraMessages: extraMessages, additionalInfo: additionalInfo, level: .error)
        }
    }

    private func dictionaryToJSONString(_ dictionary: [String: Any]?) -> String? {
        guard let dictionary, !dictionary.isEmpty else { return nil }
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dictionary, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8)
            return jsonString
        } catch {
            print("Error converting dictionary to JSON: \(error)")
            return nil
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
