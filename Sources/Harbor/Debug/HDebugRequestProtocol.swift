//
//  HDebugRequestProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import LogBird

// MARK: - Debug Protocol

/// Protocol for adding debug capabilities to network requests.
/// Implement this protocol to enable detailed logging of requests and responses.
///
/// Example usage:
/// ```swift
/// struct MyRequest: HGetRequestProtocol, HDebugRequestProtocol {
///     var debugType: HDebugRequestType = .requestAndResponse
///     // ... other properties
/// }
/// ```
public protocol HDebugRequestProtocol: Sendable {
    /// The type of debug information to log.
    var debugType: HDebugRequestType { get }
}

// MARK: - Default Implementation

/// Default implementation providing `.requestAndResponse` as the default debug type.
/// This ensures comprehensive logging by default while allowing customization.
public extension HDebugRequestProtocol {
    /// Default: `.requestAndResponse`.
    var debugType: HDebugRequestType { .requestAndResponse }
}

// MARK: - Debug Type

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

// MARK: - Logging Helpers

/// Debug logging helpers. These methods are intentionally not actor-isolated so
/// adopters can call them from any context; access to Harbor's actor-isolated
/// configuration and logger is awaited where needed.
extension HDebugRequestProtocol {

    /// Maximum number of characters of a logged body kept before truncation.
    private static var maxLoggedBodyLength: Int { 16 * 1024 }

    /// Prints detailed request information to the console.
    ///
    /// Every printed value goes through `HRedactionPolicy`: sensitive headers, query values
    /// and path/query/body parameters are replaced with `<redacted>` unless
    /// `Harbor.setLogSensitiveValues(true)` is set.
    /// - Parameter urlRequest: The URL request to debug.
    func logRequest(urlRequest: URLRequest) async {
        // Gate before building the payload: serializing parameters and
        // generating the cURL is wasted work when logging is disabled.
        guard await HLogger.isLoggingEnabled else { return }
        if let request = self as? HRequestBaseRequestProtocol,
           self.debugType == .request || self.debugType == .requestAndResponse {
            let policy = HRedactionPolicy.current
            var additionalInfo: [String: LBValue] = [:]
            additionalInfo["request"] = .string(String(describing: type(of: self)))
            if let url = urlRequest.url {
                additionalInfo["url"] = .string(policy.redactedURLString(url))
            }
            additionalInfo["httpMethod"] = .string(request.httpMethod.rawValue)

            if let headers = await dictionaryToJSONString(policy.redactedHeaders(urlRequest.allHTTPHeaderFields)) {
                additionalInfo["headerParameters"] = .string(headers)
            }

            if let pathParameters = await dictionaryToJSONString(policy.redactedParameters(request.pathParameters)) {
                additionalInfo["pathParameters"] = .string(pathParameters)
            }

            if let r = self as? (any HGetRequestProtocol),
               let queryParameters = await dictionaryToJSONString(policy.redactedParameters(r.queryParameters)) {
                additionalInfo["queryParameters"] = .string(queryParameters)
            }

            if let r = self as? (any HRequestWithBodyProtocol),
               let bodyParameters = await dictionaryToJSONString(policy.redactedParameters(r.bodyParameters)) {
                additionalInfo["bodyParameters"] = .string(bodyParameters)
            }

            additionalInfo["needsAuth"] = .bool(request.needsAuth)

            let curl = await self.generateCurl(urlRequest: urlRequest)
            let extraMessages: [LBExtraMessage] = [LBExtraMessage(key: "cURL", value: curl)]

            await HLogger.log("Request \(String(describing: type(of: request)))", extraMessages: extraMessages, additionalInfo: additionalInfo, level: .debug)
        }
    }

    /// Prints detailed response information to the console. The response headers (e.g.
    /// `Set-Cookie`) and body are redacted with `HRedactionPolicy`.
    /// - Parameters:
    ///   - httpResponse: The HTTP response received.
    ///   - data: The response data.
    ///   - duration: The request duration in milliseconds.
    func logResponse(httpResponse: HTTPURLResponse, data: Data, duration: Double) async {
        // Gate before redacting/parsing the body: JSONSerialization of every
        // response is wasted work when logging is disabled.
        guard await HLogger.isLoggingEnabled else { return }
        if self.debugType == .response || self.debugType == .requestAndResponse {
            let policy = HRedactionPolicy.current
            var extraMessages: [LBExtraMessage] = []
            if let value = await redactedResponseBody(data: data, httpResponse: httpResponse) {
                extraMessages.append(LBExtraMessage(key: "Response Value", value: value))
            }

            if let headers = await dictionaryToJSONString(redactedResponseHeaders(httpResponse, policy: policy)) {
                extraMessages.append(LBExtraMessage(key: "Response Headers", value: headers))
            }

            var additionalInfo: [String: LBValue] = [:]
            additionalInfo["request"] = .string(String(describing: type(of: self)))
            additionalInfo["statusCode"] = .int(httpResponse.statusCode)
            if let url = httpResponse.url {
                additionalInfo["url"] = .string(policy.redactedURLString(url))
            }
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
    ///
    /// Dictionaries holding values JSON cannot represent (`Date`, `Data`, NaN or infinite
    /// numbers, custom types) are never handed to `JSONSerialization`, which would raise an
    /// uncatchable Objective-C exception; a placeholder naming the problem is returned instead.
    /// - Parameter dictionary: The dictionary to convert to JSON.
    /// - Returns: A JSON string representation of the dictionary, a placeholder when it is not
    ///   JSON-serializable, or nil if it is empty or conversion fails.
    internal func dictionaryToJSONString(_ dictionary: [String: Any]?) async -> String? {
        guard let dictionary, !dictionary.isEmpty else { return nil }
        guard JSONSerialization.isValidJSONObject(dictionary) else {
            return Self.unserializablePlaceholder(for: dictionary)
        }
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys, .withoutEscapingSlashes])
            let jsonString = String(data: jsonData, encoding: .utf8)
            return jsonString
        } catch {
            await HLogger.log("Error converting dictionary to JSON", error: error)
            return nil
        }
    }

    /// Placeholder describing a dictionary that cannot be serialized as JSON. Only key names
    /// and value types are listed, never values.
    /// - Parameter dictionary: The dictionary that failed validation.
    private static func unserializablePlaceholder(for dictionary: [String: Any]) -> String {
        let fields = dictionary.keys.sorted().map { key in
            "\(key): \(type(of: dictionary[key]!))"
        }
        return "<not JSON-serializable: \(fields.joined(separator: ", "))>"
    }

    /// Generates a cURL command string equivalent to the given URL request.
    /// This is useful for debugging and reproducing requests outside of the application.
    /// Sensitive headers, cookies, query values and body fields are redacted with
    /// `HRedactionPolicy` unless `Harbor.setLogSensitiveValues(true)` is set; multipart
    /// bodies are omitted while redaction is enabled.
    /// Cookies (`-b`) are those the request's session would send: the custom session's cookie
    /// storage when one is set, otherwise `HTTPCookieStorage.shared` only when
    /// `Harbor.setHTTPShouldHandleCookies(true)` is set.
    /// Interpolated values are shell-escaped so the generated command is safe to paste.
    /// - Parameter urlRequest: The URL request to convert to cURL format.
    /// - Returns: A formatted cURL command string that can be executed in terminal.
    internal func generateCurl(urlRequest: URLRequest) async -> String {
        var components = ["$ curl -v"]

        guard let url = urlRequest.url,
              url.host != nil
        else {
            return "$ curl command could not be created"
        }

        if let httpMethod = urlRequest.httpMethod, httpMethod != "GET" {
            components.append("-X \(httpMethod)")
        }

        // Cookies and additional headers come from the session the request is sent through,
        // never from URLSession.shared: a custom session contributes its own configuration;
        // Harbor's own sessions only send cookies from HTTPCookieStorage.shared when cookie
        // handling is enabled (see Harbor.setHTTPShouldHandleCookies(_:)) and add no headers.
        let customConfiguration = await HConfig.shared.customURLSession?.configuration
        let cookieStorage: HTTPCookieStorage?
        if let customConfiguration {
            cookieStorage = customConfiguration.httpShouldSetCookies ? customConfiguration.httpCookieStorage : nil
        } else {
            cookieStorage = await HConfig.shared.httpShouldHandleCookies ? HTTPCookieStorage.shared : nil
        }
        let policy = HRedactionPolicy.current

        if let cookies = cookieStorage?.cookies(for: url), !cookies.isEmpty {
            if !policy.isEnabled {
                let string = cookies.reduce("") { $0 + "\($1.name)=\($1.value);" }
                let cookieString = Self.shellEscapeDoubleQuoted(String(string.dropLast()))
                components.append("-b \"\(cookieString)\"")
            } else {
                components.append("-b \"\(HRedactionPolicy.placeholder)\"")
            }
        }

        var headers: [AnyHashable: Any] = [:]

        customConfiguration?.httpAdditionalHeaders?.filter {  $0.0 != AnyHashable("Cookie") }
            .forEach { headers[$0.0] = $0.1 }

        urlRequest.allHTTPHeaderFields?.filter { $0.0 != "Cookie" }
            .forEach { headers[$0.0] = $0.1 }

        for header in headers {
            let name = String(describing: header.key)
            let value = policy.redactedHeaderValue(name: name, value: String(describing: header.value))
            components.append("-H \"\(Self.shellEscapeDoubleQuoted(name)): \(Self.shellEscapeDoubleQuoted(value))\"")
        }

        if let httpBodyData = urlRequest.httpBody,
           let httpBody = Self.curlBody(httpBodyData, contentType: urlRequest.value(forHTTPHeaderField: "Content-Type"), policy: policy) {
            components.append("-d \(Self.shellEscapeSingleQuoted(httpBody))")
        }

        components.append("\"\(Self.shellEscapeDoubleQuoted(policy.redactedURLString(url)))\"")

        return components.joined(separator: " \\\n\t")
    }

    /// The body printed in a cURL `-d` argument, redacted with `policy`.
    /// - Parameters:
    ///   - data: The request body.
    ///   - contentType: The request's `Content-Type`.
    ///   - policy: The redaction policy.
    /// - Returns: The printable body, or `nil` for non-UTF-8 bodies.
    private static func curlBody(_ data: Data, contentType: String?, policy: HRedactionPolicy) -> String? {
        guard let body = String(data: data, encoding: .utf8) else { return nil }
        guard policy.isEnabled else { return body }
        if contentType?.lowercased().hasPrefix("multipart/") == true {
            // Text parts can hold credentials (e.g. a password field) and file parts arbitrary data.
            return "<multipart body: \(data.count) bytes omitted>"
        }
        return policy.redactedBody(body) ?? "<\(data.count) bytes of unparseable JSON omitted>"
    }

    /// Returns the value to print for a header in debug output, redacting sensitive ones
    /// (see `HRedactionPolicy`) unless `Harbor.setLogSensitiveValues(true)` is set.
    /// - Parameters:
    ///   - name: The header name.
    ///   - value: The header value.
    /// - Returns: The value, or `<redacted>` when the header is sensitive.
    internal func redactedHeaderValue(name: String, value: String) async -> String {
        HRedactionPolicy.current.redactedHeaderValue(name: name, value: value)
    }

    /// Returns a copy of the headers dictionary with sensitive values redacted,
    /// using the same rules as `redactedHeaderValue(name:value:)`.
    /// - Parameter headers: The headers to redact, or `nil` for none.
    internal func redactedHeaders(_ headers: [String: String]?) async -> [String: String]? {
        HRedactionPolicy.current.redactedHeaders(headers)
    }

    /// Returns the response headers as a string dictionary with sensitive values (e.g.
    /// `Set-Cookie`) redacted.
    /// - Parameters:
    ///   - httpResponse: The response whose `allHeaderFields` are converted and redacted.
    ///   - policy: The redaction policy.
    internal func redactedResponseHeaders(_ httpResponse: HTTPURLResponse, policy: HRedactionPolicy) -> [String: String]? {
        var headers: [String: String] = [:]
        for (name, value) in httpResponse.allHeaderFields {
            headers[String(describing: name)] = String(describing: value)
        }
        return policy.redactedHeaders(headers)
    }

    /// Builds the debug string for a response body.
    ///
    /// The body is decoded as UTF-8; non-UTF-8 (binary) content is represented as
    /// `<binary N bytes>`. Values of sensitive keys (e.g. login/refresh tokens) are replaced
    /// with `<redacted>` at any nesting depth in JSON bodies and in form-encoded bodies, unless
    /// `Harbor.setLogSensitiveValues(true)` is set; a JSON body that cannot be parsed is omitted.
    /// Bodies longer than 16 K characters are truncated.
    /// - Parameters:
    ///   - data: The raw response body.
    ///   - httpResponse: The response the body belongs to.
    /// - Returns: The printable, redacted body.
    internal func redactedResponseBody(data: Data, httpResponse: HTTPURLResponse) async -> String? {
        guard let raw = String(data: data, encoding: .utf8) else {
            return "<binary \(data.count) bytes>"
        }

        let policy = HRedactionPolicy.current
        let body = policy.redactedBody(raw) ?? "<\(data.count) bytes of unparseable JSON omitted>"
        return Self.truncatedBody(body)
    }

    /// Truncates `body` to the maximum logged length, appending a marker when cut.
    /// - Parameter body: The already redacted body.
    private static func truncatedBody(_ body: String) -> String {
        guard body.count > maxLoggedBodyLength else { return body }
        return String(body.prefix(maxLoggedBodyLength)) + "… <truncated>"
    }

    /// Escapes `value` for use inside a double-quoted shell argument.
    /// - Parameter value: The text to embed.
    private static func shellEscapeDoubleQuoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }

    /// Quotes `value` as a single-quoted shell argument, escaping embedded
    /// single quotes. Inside single quotes no other character needs escaping.
    /// - Parameter value: The text to quote.
    private static func shellEscapeSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
