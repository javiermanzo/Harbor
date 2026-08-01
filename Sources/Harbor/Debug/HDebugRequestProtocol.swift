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
/// 
/// Example usage:
/// ```swift
/// struct MyRequest: HRequestProtocol, HDebugRequestProtocol {
///     var debugType: HDebugRequestType = .requestAndResponse
///     // ... other properties
/// }
/// ```
public protocol HDebugRequestProtocol {
    /// The type of debug information to log.
    var debugType: HDebugRequestType { get }
}

/// Default implementation providing `.requestAndResponse` as the default debug type.
/// This ensures comprehensive logging by default while allowing customization.
public extension HDebugRequestProtocol {
    var debugType: HDebugRequestType { .requestAndResponse }
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
extension HDebugRequestProtocol {
    
    /// Shared logger instance for debug output using LogBird framework.
    /// Uses "com.harbor" subsystem with "debugging" category for organized log filtering.
    static var logger: LogBird { LogBird(subsystem: "com.harbor", category: "debugging") }
    
    /// Prints detailed request information to the console.
    /// - Parameter urlRequest: The URL request to debug.
    func logRequest(urlRequest: URLRequest) {
        #if DEBUG
        guard HConfig.shared.isLoggingEnabled else { return }
        if let request = self as? HRequestBaseRequestProtocol,
           self.debugType == .request || self.debugType == .requestAndResponse {
            var additionalInfo: [String: String] = [:]
            additionalInfo["request"] = String(describing: type(of: self))
            additionalInfo["url"] = urlRequest.url?.absoluteString
            additionalInfo["httpMethod"] = request.httpMethod.rawValue
            
            if let headers = dictionaryToJSONString(redactedHeaders(urlRequest.allHTTPHeaderFields)) {
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
            
            Self.logger.log("Request \(String(describing: type(of: request)))", extraMessages: extraMessages, additionalInfo: additionalInfo, level: .debug)
        }
        #endif
    }
    
    /// Prints detailed response information to the console.
    /// - Parameters:
    ///   - httpResponse: The HTTP response received.
    ///   - data: The response data.
    ///   - duration: The request duration in milliseconds.
    func logResponse(httpResponse: HTTPURLResponse, data: Data, duration: Double) {
        #if DEBUG
        guard HConfig.shared.isLoggingEnabled else { return }
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
            
            Self.logger.log("Response \(String(describing: type(of: self)))", extraMessages: extraMessages, additionalInfo: additionalInfo, level: .debug)
        }
        #endif
    }
    
    /// Prints error response information to the console.
    /// - Parameter error: The error that occurred during the request.
    func logErrorResponse(error: HRequestError) {
        #if DEBUG
        guard HConfig.shared.isLoggingEnabled else { return }
        if self.debugType == .response || self.debugType == .requestAndResponse {
            var extraMessages: [LBExtraMessage] = []
            
            extraMessages.append(LBExtraMessage(title: "Error Type", message: "\(error)"))
            
            var additionalInfo: [String: String] = [:]
            additionalInfo["request"] = String(describing: type(of: self))
            
            Self.logger.log("Response Error \(String(describing: type(of: self)))", extraMessages: extraMessages, additionalInfo: additionalInfo, level: .error)
        }
        #endif
    }
    
    /// Converts a dictionary to a JSON string representation.
    /// - Parameter dictionary: The dictionary to convert to JSON.
    /// - Returns: A JSON string representation of the dictionary, or nil if conversion fails.
    internal func dictionaryToJSONString(_ dictionary: [String: Any]?) -> String? {
        guard let dictionary, !dictionary.isEmpty else { return nil }
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dictionary, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8)
            return jsonString
        } catch {
            #if DEBUG
            if HConfig.shared.isLoggingEnabled {
                Self.logger.log("Error converting dictionary to JSON", error: error)
            }
            #endif
            return nil
        }
    }
    
    /// Generates a cURL command string equivalent to the given URL request.
    /// This is useful for debugging and reproducing requests outside of the application.
    /// Sensitive headers and cookies are redacted unless `Harbor.setLogSensitiveHeaders(true)` is set.
    /// - Parameter urlRequest: The URL request to convert to cURL format.
    /// - Returns: A formatted cURL command string that can be executed in terminal.
    internal func generateCurl(urlRequest: URLRequest) -> String {
        var components = ["$ curl -v"]

        guard let url = urlRequest.url,
              let _ = url.host
        else {
            return "$ curl command could not be created"
        }

        if let httpMethod = urlRequest.httpMethod, httpMethod != "GET" {
            components.append("-X \(httpMethod)")
        }

        // Read cookies and additional headers from Harbor's actual session, never from URLSession.shared
        let sessionConfiguration = HConfig.shared.currentURLSession?.configuration

        if sessionConfiguration?.httpShouldSetCookies == true {
            if let cookieStorage = sessionConfiguration?.httpCookieStorage,
               let cookies = cookieStorage.cookies(for: url), !cookies.isEmpty {
                if HConfig.shared.logSensitiveHeaders {
                    let string = cookies.reduce("") { $0 + "\($1.name)=\($1.value);" }
                    components.append("-b \"\(string[..<string.index(before: string.endIndex)])\"")
                } else {
                    components.append("-b \"<redacted>\"")
                }
            }
        }

        var headers: [AnyHashable: Any] = [:]

        sessionConfiguration?.httpAdditionalHeaders?.filter {  $0.0 != AnyHashable("Cookie") }
            .forEach { headers[$0.0] = $0.1 }

        urlRequest.allHTTPHeaderFields?.filter { $0.0 != "Cookie" }
            .forEach { headers[$0.0] = $0.1 }

        components += headers.map {
            let value = redactedHeaderValue(name: String(describing: $0.key), value: String(describing: $0.value))
            let escapedValue = value.replacingOccurrences(of: "\"", with: "\\\"")

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

    /// Returns the value to print for a header in debug output, redacting sensitive ones
    /// (case-insensitive) unless `HConfig.logSensitiveHeaders` is enabled.
    internal func redactedHeaderValue(name: String, value: String) -> String {
        if !HConfig.shared.logSensitiveHeaders && HConfig.sensitiveHeaders.contains(name.lowercased()) {
            return "<redacted>"
        }
        return value
    }

    /// Returns a copy of the headers dictionary with sensitive values redacted,
    /// using the same rules as `redactedHeaderValue(name:value:)`.
    internal func redactedHeaders(_ headers: [String: String]?) -> [String: String]? {
        headers?.reduce(into: [String: String]()) { result, header in
            result[header.key] = redactedHeaderValue(name: header.key, value: header.value)
        }
    }
}
