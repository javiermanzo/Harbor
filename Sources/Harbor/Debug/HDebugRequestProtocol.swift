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
public protocol HDebugRequestProtocol: Sendable {
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

/// Debug logging helpers. These methods are intentionally not actor-isolated so
/// adopters can call them from any context; access to Harbor's actor-isolated
/// configuration and logger is awaited where needed.
extension HDebugRequestProtocol {

    /// Maximum number of characters of a logged body kept before truncation.
    private static var maxLoggedBodyLength: Int { 16 * 1024 }

    /// Prints detailed request information to the console.
    /// - Parameter urlRequest: The URL request to debug.
    func logRequest(urlRequest: URLRequest) async {
        // Gate before building the payload: serializing parameters and
        // generating the cURL is wasted work when logging is disabled.
        guard await HLogger.isLoggingEnabled else { return }
        if let request = self as? HRequestBaseRequestProtocol,
           self.debugType == .request || self.debugType == .requestAndResponse {
            var additionalInfo: [String: LBValue] = [:]
            additionalInfo["request"] = .string(String(describing: type(of: self)))
            if let urlString = urlRequest.url?.absoluteString {
                additionalInfo["url"] = .string(urlString)
            }
            additionalInfo["httpMethod"] = .string(request.httpMethod.rawValue)

            if let headers = await dictionaryToJSONString(redactedHeaders(urlRequest.allHTTPHeaderFields)) {
                additionalInfo["headerParameters"] = .string(headers)
            }

            if let pathParameters = await dictionaryToJSONString(request.pathParameters) {
                additionalInfo["pathParameters"] = .string(pathParameters)
            }

            if let r = self as? (any HGetRequestProtocol),
               let queryParameters = await dictionaryToJSONString(r.queryParameters) {
                additionalInfo["queryParameters"] = .string(queryParameters)
            }

            if let r = self as? (any HRequestWithBodyProtocol),
               let bodyParameters = await dictionaryToJSONString(r.bodyParameters) {
                additionalInfo["bodyParameters"] = .string(bodyParameters)
            }

            additionalInfo["needsAuth"] = .bool(request.needsAuth)

            let curl = await self.generateCurl(urlRequest: urlRequest)
            let extraMessages: [LBExtraMessage] = [LBExtraMessage(key: "cURL", value: curl)]

            await HLogger.log("Request \(String(describing: type(of: request)))", extraMessages: extraMessages, additionalInfo: additionalInfo, level: .debug)
        }
    }

    /// Prints detailed response information to the console.
    /// - Parameters:
    ///   - httpResponse: The HTTP response received.
    ///   - data: The response data.
    ///   - duration: The request duration in milliseconds.
    func logResponse(httpResponse: HTTPURLResponse, data: Data, duration: Double) async {
        // Gate before redacting/parsing the body: JSONSerialization of every
        // response is wasted work when logging is disabled.
        guard await HLogger.isLoggingEnabled else { return }
        if self.debugType == .response || self.debugType == .requestAndResponse {
            var extraMessages: [LBExtraMessage] = []
            if let value = await redactedResponseBody(data: data, httpResponse: httpResponse) {
                extraMessages.append(LBExtraMessage(key: "Response Value", value: value))
            }

            extraMessages.append(LBExtraMessage(key: "Response Object", value: httpResponse.debugDescription))

            var additionalInfo: [String: LBValue] = [:]
            additionalInfo["request"] = .string(String(describing: type(of: self)))
            additionalInfo["size"] = .string(data.debugDescription)
            additionalInfo["duration"] = .string("\(String(format: "%.2f", duration))ms")

            await HLogger.log("Response \(String(describing: type(of: self)))", extraMessages: extraMessages, additionalInfo: additionalInfo, level: .debug)
        }
    }

    /// Prints error response information to the console.
    ///
    /// Errors are logged regardless of `debugType` so failures are never silently
    /// swallowed; only the `isLoggingEnabled` gate applies.
    /// - Parameter error: The error that occurred during the request.
    func logErrorResponse(error: HRequestError) async {
        guard await HLogger.isLoggingEnabled else { return }
        var extraMessages: [LBExtraMessage] = []

        extraMessages.append(LBExtraMessage(key: "Error Type", value: "\(error)"))

        var additionalInfo: [String: LBValue] = [:]
        additionalInfo["request"] = .string(String(describing: type(of: self)))

        await HLogger.log("Response Error \(String(describing: type(of: self)))", extraMessages: extraMessages, additionalInfo: additionalInfo, level: .error)
    }

    /// Converts a dictionary to a JSON string representation with sorted keys,
    /// so the output is deterministic.
    /// - Parameter dictionary: The dictionary to convert to JSON.
    /// - Returns: A JSON string representation of the dictionary, or nil if conversion fails.
    internal func dictionaryToJSONString(_ dictionary: [String: Any]?) async -> String? {
        guard let dictionary, !dictionary.isEmpty else { return nil }
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
            let jsonString = String(data: jsonData, encoding: .utf8)
            return jsonString
        } catch {
            await HLogger.log("Error converting dictionary to JSON", error: error)
            return nil
        }
    }

    /// Generates a cURL command string equivalent to the given URL request.
    /// This is useful for debugging and reproducing requests outside of the application.
    /// Sensitive headers and cookies are redacted unless `Harbor.setLogSensitiveHeaders(true)` is set.
    /// Interpolated values are shell-escaped so the generated command is safe to paste.
    /// - Parameter urlRequest: The URL request to convert to cURL format.
    /// - Returns: A formatted cURL command string that can be executed in terminal.
    internal func generateCurl(urlRequest: URLRequest) async -> String {
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
        let sessionConfiguration = await HConfig.shared.customURLSession?.configuration ?? .default
        let logSensitiveHeaders = await HConfig.shared.logSensitiveHeaders

        if sessionConfiguration.httpShouldSetCookies == true {
            if let cookieStorage = sessionConfiguration.httpCookieStorage,
               let cookies = cookieStorage.cookies(for: url), !cookies.isEmpty {
                if logSensitiveHeaders {
                    let string = cookies.reduce("") { $0 + "\($1.name)=\($1.value);" }
                    let cookieString = Self.shellEscapeDoubleQuoted(String(string.dropLast()))
                    components.append("-b \"\(cookieString)\"")
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

        for header in headers {
            let name = String(describing: header.key)
            let value = await redactedHeaderValue(name: name, value: String(describing: header.value))
            components.append("-H \"\(Self.shellEscapeDoubleQuoted(name)): \(Self.shellEscapeDoubleQuoted(value))\"")
        }

        if let httpBodyData = urlRequest.httpBody, let httpBody = String(data: httpBodyData, encoding: .utf8) {
            components.append("-d \(Self.shellEscapeSingleQuoted(httpBody))")
        }

        components.append("\"\(Self.shellEscapeDoubleQuoted(url.absoluteString))\"")

        return components.joined(separator: " \\\n\t")
    }

    /// Returns the value to print for a header in debug output, redacting sensitive ones
    /// (case-insensitive) unless `HConfig.logSensitiveHeaders` is enabled.
    internal func redactedHeaderValue(name: String, value: String) async -> String {
        let logSensitiveHeaders = await HConfig.shared.logSensitiveHeaders
        let sensitiveHeaders = await HConfig.sensitiveHeaders
        if !logSensitiveHeaders && sensitiveHeaders.contains(name.lowercased()) {
            return "<redacted>"
        }
        return value
    }

    /// Returns a copy of the headers dictionary with sensitive values redacted,
    /// using the same rules as `redactedHeaderValue(name:value:)`.
    internal func redactedHeaders(_ headers: [String: String]?) async -> [String: String]? {
        guard let headers else { return nil }
        let logSensitiveHeaders = await HConfig.shared.logSensitiveHeaders
        let sensitiveHeaders = await HConfig.sensitiveHeaders
        return headers.reduce(into: [String: String]()) { result, header in
            if !logSensitiveHeaders && sensitiveHeaders.contains(header.key.lowercased()) {
                result[header.key] = "<redacted>"
            } else {
                result[header.key] = header.value
            }
        }
    }

    /// Builds the debug string for a response body.
    ///
    /// The body is decoded as UTF-8; non-UTF-8 (binary) content is represented as
    /// `<binary N bytes>`. When the body parses as JSON, values of sensitive keys
    /// (e.g. login/refresh tokens) are replaced with `<redacted>` at any nesting
    /// depth, unless `HConfig.logSensitiveHeaders` is enabled. Bodies longer than
    /// 16 KB are truncated.
    internal func redactedResponseBody(data: Data, httpResponse: HTTPURLResponse) async -> String? {
        guard let raw = String(data: data, encoding: .utf8) else {
            return "<binary \(data.count) bytes>"
        }

        var body = raw
        let logSensitiveHeaders = await HConfig.shared.logSensitiveHeaders
        if !logSensitiveHeaders {
            let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            if contentType.contains("json") || HJSONRedactor.looksLikeJSON(raw) {
                body = HJSONRedactor.redactedBody(raw, needles: await HLogger.sensitiveKeys)
            }
        }

        return Self.truncatedBody(body)
    }

    /// Truncates `body` to the maximum logged length, appending a marker when cut.
    private static func truncatedBody(_ body: String) -> String {
        guard body.count > maxLoggedBodyLength else { return body }
        return String(body.prefix(maxLoggedBodyLength)) + "… <truncated>"
    }

    /// Escapes `value` for use inside a double-quoted shell argument.
    private static func shellEscapeDoubleQuoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }

    /// Quotes `value` as a single-quoted shell argument, escaping embedded
    /// single quotes. Inside single quotes no other character needs escaping.
    private static func shellEscapeSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
