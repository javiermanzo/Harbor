//
//  HJSONValue.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation

/// A type-safe representation of any JSON value.
///
/// Used to carry arbitrary JSON payloads in JSON-RPC requests and responses
/// (for example, the `data` field of a JSON-RPC error) without relying on `Any`.
public enum HJSONValue: Sendable, Equatable {
    /// A JSON `null` value.
    case null
    /// A JSON boolean value.
    case bool(Bool)
    /// A JSON integer number.
    case int(Int)
    /// A JSON floating-point number.
    case double(Double)
    /// A JSON string.
    case string(String)
    /// A JSON array.
    case array([HJSONValue])
    /// A JSON object.
    case object([String: HJSONValue])
}

// MARK: - Codable

extension HJSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([HJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: HJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "The value is not a valid JSON value.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

// MARK: - JSONSerialization Bridge

extension HJSONValue {
    /// The value mapped to a `JSONSerialization`-compatible object graph.
    var anyValue: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return values.map { $0.anyValue }
        case .object(let object):
            return object.mapValues { $0.anyValue }
        }
    }

    /// Creates a JSON value from a `JSONSerialization` object graph.
    /// - Parameter anyValue: An object produced by `JSONSerialization` (`NSNull`, `Bool`, `String`, `NSNumber`, `[Any]` or `[String: Any]`).
    init?(anyValue: Any) {
        switch anyValue {
        case is NSNull:
            self = .null
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else if CFNumberIsFloatType(value) {
                self = .double(value.doubleValue)
            } else {
                self = .int(value.intValue)
            }
        case let value as [Any]:
            self = .array(value.compactMap { HJSONValue(anyValue: $0) })
        case let value as [String: Any]:
            self = .object(value.compactMapValues { HJSONValue(anyValue: $0) })
        default:
            return nil
        }
    }
}
