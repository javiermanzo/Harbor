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
    
    /// Prints detailed request information to the console.
    /// - Parameter urlRequest: The URL request to debug.
    func logRequest(urlRequest: URLRequest) {
        // Gate before building the payload: serializing parameters and
        // generating the cURL is wasted work when logging is disabled.
        guard HarborLogger.isLoggingEnabled else { return }
        if let request = self as? HRequestBaseRequestProtocol,
           self.debugType == .request || self.debugType == .requestAndResponse {
            var additionalInfo: [String: LBValue] = [:]
            additionalInfo["request"] = .string(String(describing: type(of: self)))
            if let urlString = urlRequest.url?.absoluteString {
                additionalInfo["url"] = .string(urlString)
            }
            additionalInfo["httpMethod"] = .string(request.httpMethod.rawValue)
            
            if let headers = dictionaryToJSONString(redactedHeaders(urlRequest.allHTTPHeaderFields)) {
                additionalInfo["headerParameters"] = .string(headers)
            }
            
            if let pathParameters = dictionaryToJSONString(request.pathParameters) {
                additionalInfo["pathParameters"] = .string(pathParameters)
            }
            
            if let r = self as? (any HGetRequestProtocol),
               let queryParameters = dictionaryToJSONString(r.queryParameters) {
                additionalInfo["queryParameters"] = .string(queryParameters)
            }
            
            if let r = self as? (any HRequestWithBodyProtocol),
               let bodyParameters = dictionaryToJSONString(r.bodyParameters) {
                additionalInfo["bodyParameters"] = .string(bodyParameters)
            }
            
            additionalInfo["needsAuth"] = .bool(request.needsAuth)
            
            let curl = self.generateCurl(urlRequest: urlRequest)
            let extraMessages: [LBExtraMessage] = [LBExtraMessage(key: "cURL", value: curl)]
            
            HarborLogger.log("Request \(String(describing: type(of: request)))", extraMessages: extraMessages, additionalInfo: additionalInfo, level: .debug)
        }
    }
    
    /// Prints detailed response information to the console.
    /// - Parameters:
    ///   - httpResponse: The HTTP response received.
    ///   - data: The response data.
    ///   - duration: The request duration in milliseconds.
    func logResponse(httpResponse: HTTPURLResponse, data: Data, duration: Double) {
        // Gate before redacting/parsing the body: JSONSerialization of every
        // response is wasted work when logging is disabled.
        guard HarborLogger.isLoggingEnabled else { return }
        if self.debugType == .response || self.debugType == .requestAndResponse {
            var extraMessages: [LBExtraMessage] = []
            if let value = redactedResponseBody(data: data, httpResponse: httpResponse) {
                extraMessages.append(LBExtraMessage(key: "Response Value", value: value))
            }
            
            extraMessages.append(LBExtraMessage(key: "Response Object", value: httpResponse.debugDescription))
            
            var additionalInfo: [String: LBValue] = [:]
            additionalInfo["request"] = .string(String(describing: type(of: self)))
            additionalInfo["size"] = .string(data.debugDescription)
            additionalInfo["duration"] = .string("\(String(format: "%.2f", duration))ms")
            
            HarborLogger.log("Response \(String(describing: type(of: self)))", extraMessages: extraMessages, additionalInfo: additionalInfo, level: .debug)
        }
    }
    
    /// Prints error response information to the console.
    ///
    /// Errors are logged regardless of `debugType` so failures are never silently
    /// swallowed; only the `isLoggingEnabled` gate applies.
    /// - Parameter error: The error that occurred during the request.
    func logErrorResponse(error: HRequestError) {
        guard HarborLogger.isLoggingEnabled else { return }
        var extraMessages: [LBExtraMessage] = []

        extraMessages.append(LBExtraMessage(key: "Error Type", value: "\(error)"))

        var additionalInfo: [String: LBValue] = [:]
        additionalInfo["request"] = .string(String(describing: type(of: self)))

        HarborLogger.log("Response Error \(String(describing: type(of: self)))", extraMessages: extraMessages, additionalInfo: additionalInfo, level: .error)
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
            HarborLogger.log("Error converting dictionary to JSON", error: error)
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

        // Read cookies and additional headers from Harbor's session configuration, never from URLSession.shared
        let sessionConfiguration = HConfig.shared.customURLSession?.configuration ?? .default

        if sessionConfiguration.httpShouldSetCookies == true {
            if let cookieStorage = sessionConfiguration.httpCookieStorage,
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

        sessionConfiguration.httpAdditionalHeaders?.filter {  $0.0 != AnyHashable("Cookie") }
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

    /// Builds the debug string for a response body, redacting sensitive values
    /// when the body is JSON (e.g. login/refresh tokens) unless
    /// `HConfig.logSensitiveHeaders` is enabled. Non-JSON bodies are returned
    /// as-is; if JSON parsing fails the raw body is returned.
    internal func redactedResponseBody(data: Data, httpResponse: HTTPURLResponse) -> String? {
        guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else { return nil }
        if HConfig.shared.logSensitiveHeaders { return raw }

        let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard contentType.contains("json") || Self.looksLikeJSON(raw),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return raw
        }

        let needles = HarborLogger.sensitiveKeys
        let redacted = Self.redactJSONValue(parsed, needles: needles)
        guard JSONSerialization.isValidJSONObject(redacted),
              let redactedData = try? JSONSerialization.data(withJSONObject: redacted, options: []),
              let redactedString = String(data: redactedData, encoding: .utf8) else {
            return raw
        }
        return redactedString
    }

    /// True when `s` starts with `{` or `[` after trimming whitespace.
    private static func looksLikeJSON(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first == "{" || trimmed.first == "["
    }

    /// Recursively redacts sensitive values within a parsed JSON object/array.
    /// A key is sensitive when it contains any of `needles` after normalization
    /// (mirrors LogBird's matching).
    private static func redactJSONValue(_ value: Any, needles: Set<String>) -> Any {
        if let dict = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, nested) in dict {
                result[key] = isSensitiveKey(key, needles: needles) ? "<redacted>" : redactJSONValue(nested, needles: needles)
            }
            return result
        } else if let array = value as? [Any] {
            return array.map { redactJSONValue($0, needles: needles) }
        }
        return value
    }

    /// Normalizes `key` (lowercase, stripping `-`, `_` and whitespace) and
    /// returns whether it contains any of `needles`.
    private static func isSensitiveKey(_ key: String, needles: Set<String>) -> Bool {
        let normalized = key.lowercased().filter { $0 != "_" && $0 != "-" && !$0.isWhitespace }
        return needles.contains { normalized.contains($0) }
    }
}
