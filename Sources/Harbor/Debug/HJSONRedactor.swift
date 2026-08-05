//
//  HJSONRedactor.swift
//  Harbor
//
//  Shared sensitive-key redaction for JSON payloads.
//

import Foundation

/// Redacts sensitive values in JSON payloads. Shared by the debug response logger and
/// `HRequestError.api` descriptions so error output follows the same redaction policy
/// as debug logs.
enum HJSONRedactor {
    /// Returns `body` with the values of sensitive keys replaced by `<redacted>` at any
    /// nesting depth when it parses as JSON; otherwise returns `body` unchanged.
    static func redactedBody(_ body: String, needles: Set<String>) -> String {
        guard looksLikeJSON(body),
              let data = body.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return body
        }

        let redacted = redactJSONValue(parsed, needles: needles)
        guard JSONSerialization.isValidJSONObject(redacted),
              let redactedData = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]),
              let redactedString = String(data: redactedData, encoding: .utf8) else {
            return body
        }
        return redactedString
    }

    /// True when `s` starts with `{` or `[` after trimming whitespace.
    static func looksLikeJSON(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first == "{" || trimmed.first == "["
    }

    /// Recursively redacts sensitive values within a parsed JSON object/array.
    /// A key is sensitive when it contains any of `needles` after normalization
    /// (mirrors LogBird's matching).
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

    /// Normalizes `key` (lowercase, stripping `-`, `_` and whitespace) and
    /// returns whether it contains any of `needles`.
    static func isSensitiveKey(_ key: String, needles: Set<String>) -> Bool {
        let normalized = key.lowercased().filter { $0 != "_" && $0 != "-" && !$0.isWhitespace }
        return needles.contains { normalized.contains($0) }
    }
}
