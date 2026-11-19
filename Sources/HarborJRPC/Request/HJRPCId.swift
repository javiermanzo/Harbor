//
//  HJRPCId.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation

/// A JSON-RPC request identifier.
///
/// The JSON-RPC 2.0 specification allows the `id` member to be a string, a number or `null`.
/// Numeric identifiers must be integers that fit in `Int`; decoding a fractional or
/// out-of-range number (e.g. `1.5` or `1e30`) throws a `DecodingError`.
public enum HJRPCId: Sendable {
    /// A string identifier.
    case string(String)
    /// A numeric identifier.
    case number(Int)
    /// An explicit `null` identifier.
    case null

    /// Generates a unique string identifier based on a UUID.
    public static func generated() -> HJRPCId {
        .string(UUID().uuidString)
    }
}

// MARK: - Equatable

extension HJRPCId: Equatable {}

// MARK: - Codable

extension HJRPCId: Codable {
    /// Decodes a string, an integer that fits in `Int`, or `null`.
    /// - Throws: `DecodingError` for any other JSON value, including fractional or out-of-range numbers.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(value)
        } else if let value = try? container.decode(Double.self), let integer = Int(exactly: value) {
            // An integral number written with a fraction or exponent (e.g. `1.0`). Numbers that
            // are fractional or outside `Int`'s range (e.g. `1e30`) are rejected below instead of
            // trapping in `Int(_:)`.
            self = .number(integer)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "The id is not a valid JSON-RPC identifier: it must be a string, null or an integer that fits in Int.")
        }
    }

    /// Encodes the identifier as a JSON string, number or `null`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

// MARK: - CustomStringConvertible

extension HJRPCId: CustomStringConvertible {
    /// The identifier as it appears in JSON: a quoted string, a number or `null`.
    public var description: String {
        switch self {
        case .string(let value):
            return "\"\(value)\""
        case .number(let value):
            return String(value)
        case .null:
            return "null"
        }
    }
}

// MARK: - JSON Value Bridge

extension HJRPCId {
    /// The identifier represented as an `HJSONValue`.
    var jsonValue: HJSONValue {
        switch self {
        case .string(let value):
            return .string(value)
        case .number(let value):
            return .int(value)
        case .null:
            return .null
        }
    }
}
