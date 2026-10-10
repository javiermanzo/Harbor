//
//  HJSONRedactor.swift
//  Harbor
//
//  Shared sensitive-key redaction for JSON payloads.
//

import Foundation

/// Redacts sensitive values in JSON payloads. Used through `HRedactionPolicy` by the debug
/// logger (request body parameters, cURL bodies, response bodies) and by
/// `HRequestError.api` descriptions, so error output follows the same redaction policy as
/// debug logs.
enum HJSONRedactor {
    /// Returns `body` with the values of sensitive keys replaced by `<redacted>` at any
    /// nesting depth when it parses as JSON; otherwise returns `body` unchanged.
    /// - Parameters:
    ///   - body: The raw JSON string body.
    ///   - needles: Set of sensitive key needles to match against.
    /// - Returns: Redacted JSON string, or original string if not valid JSON.
    static func redactedBody(_ body: String, needles: Set<String>) -> String {
        redactedJSON(body, needles: needles) ?? body
    }

    /// Returns `body` with the values of sensitive keys replaced by `<redacted>` at any
    /// nesting depth, or `nil` when it does not parse as JSON. A body without sensitive keys
    /// is returned unchanged (byte for byte); otherwise it is re-serialized with sorted keys.
    /// - Parameters:
    ///   - body: The raw JSON string body.
    ///   - needles: Set of sensitive key needles to match against.
    /// - Returns: The redacted JSON string, or `nil` if `body` is not valid JSON.
    static func redactedJSON(_ body: String, needles: Set<String>) -> String? {
        guard looksLikeJSON(body),
              let data = body.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }

        guard containsSensitiveKey(parsed, needles: needles) else { return body }

        let redacted = redactJSONValue(parsed, needles: needles)
        guard JSONSerialization.isValidJSONObject(redacted),
              let redactedData = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys, .withoutEscapingSlashes]),
              let redactedString = String(data: redactedData, encoding: .utf8) else {
            return nil
        }
        return redactedString
    }

    /// Checks if a string formatted body appears to be JSON based on leading characters.
    /// - Parameter s: The input string to inspect.
    /// - Returns: `true` when string starts with `{` or `[` after trimming whitespace.
    static func looksLikeJSON(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first == "{" || trimmed.first == "["
    }

    /// Recursively redacts sensitive values within a parsed JSON object/array.
    /// A key is sensitive when it contains any of `needles` after normalization.
    /// Values that are not dictionaries or arrays (including non-JSON values such as `Date`)
    /// are returned unchanged.
    /// - Parameters:
    ///   - value: Parsed JSON object, array, or scalar.
    ///   - needles: Set of sensitive key needles to match against.
    /// - Returns: Redacted JSON object or array representation.
    static func redactJSONValue(_ value: Any, needles: Set<String>) -> Any {
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

    /// Whether a parsed JSON value contains a sensitive key at any nesting depth.
    /// - Parameters:
    ///   - value: Parsed JSON object, array, or scalar.
    ///   - needles: Set of sensitive key needles to match against.
    static func containsSensitiveKey(_ value: Any, needles: Set<String>) -> Bool {
        if let dict = value as? [String: Any] {
            return dict.contains { isSensitiveKey($0.key, needles: needles) || containsSensitiveKey($0.value, needles: needles) }
        } else if let array = value as? [Any] {
            return array.contains { containsSensitiveKey($0, needles: needles) }
        }
        return false
    }

    /// Normalizes `key` (lowercase, stripping `-`, `_` and whitespace) and
    /// returns whether it contains any of `needles`.
    /// - Parameters:
    ///   - key: The JSON field key name.
    ///   - needles: Set of sensitive key needles.
    /// - Returns: `true` if key contains any sensitive needle, `false` otherwise.
    static func isSensitiveKey(_ key: String, needles: Set<String>) -> Bool {
        let normalized = normalize(key)
        return needles.contains { !$0.isEmpty && normalized.contains($0) }
    }

    /// Lowercases `key` and strips `-`, `_` and whitespace, so written variants of the same
    /// key (`api_key`, `X-API-Key`, `API KEY`) compare equal.
    static func normalize(_ key: String) -> String {
        key.lowercased().filter { $0 != "_" && $0 != "-" && !$0.isWhitespace }
    }
}
