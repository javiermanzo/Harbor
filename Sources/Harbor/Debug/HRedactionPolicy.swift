//
//  HRedactionPolicy.swift
//  Harbor
//
//  Single redaction policy shared by debug logs, generated cURL commands and error descriptions.
//

import Foundation
import LogBird

/// Harbor's single redaction policy for everything it prints: logged request headers, query
/// values, path/query/body parameters, generated cURL commands, response headers and bodies,
/// and `HRequestError.api` descriptions.
///
/// A key (header name, query item name, JSON field, form field) is sensitive when, after
/// normalization (lowercased, `-`, `_` and whitespace stripped), it contains any needle from:
/// - Harbor's built-in HTTP credential keys (``defaultSensitiveKeys``), always applied;
/// - the logger's configurable keys (`Harbor.updateLogSensitiveKeys(_:)`);
/// - the header keys the auth provider's headers were sent under.
///
/// `Harbor.setLogSensitiveValues(true)` disables redaction entirely, so every value is shown.
///
/// The policy is a value snapshot. ``current`` reads the latest configuration under a lock, so
/// it can be used from nonisolated, synchronous contexts such as `HRequestError.errorDescription`.
struct HRedactionPolicy: Sendable {

    /// The string that replaces a redacted value.
    static let placeholder = "<redacted>"

    /// Built-in sensitive key needles, matched as normalized substrings. They are a floor:
    /// `Harbor.updateLogSensitiveKeys(.set/.clear)` only changes the configurable keys on top of
    /// them; use `Harbor.setLogSensitiveValues(true)` to show every value.
    static let defaultSensitiveKeys: Set<String> = Set([
        "authorization", "proxy-authorization", "cookie", "set-cookie",
        "x-api-key", "api_key", "apikey",
        "password", "passwd", "secret", "client_secret",
        "token", "access_token", "refresh_token",
        "session_id", "private_key", "credential", "signature"
    ].map(HJSONRedactor.normalize))

    /// Whether values are redacted. `false` when sensitive logging is opted in.
    let isEnabled: Bool
    /// Normalized sensitive key needles.
    let needles: Set<String>

    /// Creates a policy.
    /// - Parameters:
    ///   - isEnabled: Whether values are redacted.
    ///   - configuredKeys: Additional key needles on top of ``defaultSensitiveKeys``.
    init(isEnabled: Bool, configuredKeys: Set<String> = []) {
        self.isEnabled = isEnabled
        self.needles = Self.defaultSensitiveKeys
            .union(configuredKeys.map(HJSONRedactor.normalize))
            .filter { !$0.isEmpty }
    }

    // MARK: - Current Configuration

    /// The policy for the current configuration.
    static var current: HRedactionPolicy {
        storage.withLock { state in
            HRedactionPolicy(isEnabled: !state.logsSensitiveValues,
                             configuredKeys: state.configuredKeys.union(state.authHeaderKeys))
        }
    }

    /// Whether sensitive values are printed unredacted (`Harbor.setLogSensitiveValues(_:)`).
    static var logsSensitiveValues: Bool {
        get { storage.withLock { $0.logsSensitiveValues } }
        set { storage.withLock { $0.logsSensitiveValues = newValue } }
    }

    /// Records the sensitive keys configured on Harbor's logger.
    /// - Parameter keys: The logger's current sensitive keys.
    static func setConfiguredKeys(_ keys: Set<String>) {
        storage.withLock { $0.configuredKeys = keys }
    }

    /// Records a header key the auth provider's credential was sent under, so it is redacted
    /// even when it is not a well-known name (e.g. `X-Session-Id`).
    /// - Parameter key: The authorization header key.
    static func registerAuthHeaderKey(_ key: String) {
        let normalized = HJSONRedactor.normalize(key)
        guard !normalized.isEmpty else { return }
        storage.withLock { state in
            // Bounded: a provider uses one or a handful of header keys.
            if state.authHeaderKeys.count >= maxAuthHeaderKeys, !state.authHeaderKeys.contains(normalized) {
                state.authHeaderKeys.removeAll()
            }
            state.authHeaderKeys.insert(normalized)
        }
    }

    /// Maximum number of auth header keys remembered.
    private static let maxAuthHeaderKeys = 16

    /// Mutable configuration backing ``current``.
    private struct State {
        /// Whether sensitive values are printed unredacted.
        var logsSensitiveValues = false
        /// The configurable sensitive keys (see `Harbor.updateLogSensitiveKeys(_:)`).
        var configuredKeys: Set<String> = LogBird.defaultSensitiveKeys
        /// Header keys auth providers sent credentials under, normalized.
        var authHeaderKeys: Set<String> = []
    }

    /// Lock-protected configuration state.
    private static let storage = HLockedState(State())

    // MARK: - Keys

    /// Whether `key` is sensitive under this policy. Always `false` when redaction is disabled.
    /// - Parameter key: A header name, query item name or body field name.
    func isSensitive(_ key: String) -> Bool {
        isEnabled && HJSONRedactor.isSensitiveKey(key, needles: needles)
    }

    // MARK: - Headers

    /// Returns `value`, or the placeholder when the header `name` is sensitive.
    /// - Parameters:
    ///   - name: The header name.
    ///   - value: The header value.
    func redactedHeaderValue(name: String, value: String) -> String {
        isSensitive(name) ? Self.placeholder : value
    }

    /// Returns a copy of `headers` with the values of sensitive headers redacted.
    /// - Parameter headers: The request or response headers to redact, or `nil` for none.
    func redactedHeaders(_ headers: [String: String]?) -> [String: String]? {
        guard let headers else { return nil }
        return headers.reduce(into: [String: String]()) { result, header in
            result[header.key] = redactedHeaderValue(name: header.key, value: header.value)
        }
    }

    // MARK: - Parameters and Bodies

    /// Returns a copy of `parameters` with the values of sensitive keys redacted at any
    /// nesting depth.
    /// - Parameter parameters: Path, query or body parameters.
    func redactedParameters(_ parameters: [String: Any]?) -> [String: Any]? {
        guard let parameters, isEnabled else { return parameters }
        return HJSONRedactor.redactJSONValue(parameters, needles: needles) as? [String: Any]
    }

    /// Redacts a textual body: JSON bodies have sensitive fields redacted at any nesting depth
    /// and form-encoded bodies (`a=1&b=2`) have sensitive field values redacted. Other text is
    /// returned unchanged.
    /// - Parameter body: The body text.
    /// - Returns: The redacted body, or `nil` when it looks like JSON but cannot be parsed
    ///   (it may hold a sensitive value that cannot be located, so it must not be shown).
    func redactedBody(_ body: String) -> String? {
        guard isEnabled else { return body }
        if HJSONRedactor.looksLikeJSON(body) {
            return HJSONRedactor.redactedJSON(body, needles: needles)
        }
        return redactedFormEncoded(body) ?? body
    }

    /// Redacts the values of sensitive fields in a form-encoded string (`name=value&...`),
    /// such as a URL query or an `application/x-www-form-urlencoded` body.
    /// - Parameter string: The percent-encoded string.
    /// - Returns: The redacted string, or `nil` when `string` is not form-encoded or nothing
    ///   needed redaction.
    func redactedFormEncoded(_ string: String) -> String? {
        guard isEnabled, string.contains("="), !string.contains(where: { $0.isWhitespace }) else { return nil }
        var redactedAny = false
        let pairs = string.split(separator: "&", omittingEmptySubsequences: false).map { pair -> String in
            guard let separator = pair.firstIndex(of: "=") else { return String(pair) }
            let rawName = String(pair[..<separator])
            let name = rawName.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? rawName
            guard isSensitive(name) else { return String(pair) }
            redactedAny = true
            return "\(rawName)=\(Self.placeholder)"
        }
        return redactedAny ? pairs.joined(separator: "&") : nil
    }

    // MARK: - URLs

    /// Returns the URL string with the values of sensitive query items redacted.
    /// - Parameter url: The URL whose query string is inspected.
    func redactedURLString(_ url: URL) -> String {
        guard isEnabled,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let query = components.percentEncodedQuery,
              let redactedQuery = redactedFormEncoded(query) else {
            return url.absoluteString
        }
        let fragment = components.percentEncodedFragment
        components.percentEncodedQuery = nil
        components.percentEncodedFragment = nil
        guard let base = components.string else { return url.absoluteString }
        return base + "?" + redactedQuery + (fragment.map { "#\($0)" } ?? "")
    }

    // MARK: - Error Previews

    /// A bounded, redacted preview of a response body for error descriptions.
    /// - Parameters:
    ///   - data: The raw response body.
    ///   - limit: Maximum number of characters kept.
    /// - Returns: The preview, a byte count for non-UTF-8 data, or a placeholder for JSON-like
    ///   bodies that cannot be parsed while redaction is enabled.
    func bodyPreview(_ data: Data, limit: Int) -> String {
        guard let body = String(data: data, encoding: .utf8) else {
            return "\(data.count) bytes of non-UTF-8 data"
        }
        guard let redacted = redactedBody(body) else {
            return "<\(data.count) bytes of unparseable JSON omitted>"
        }
        return String(redacted.prefix(limit))
    }
}
