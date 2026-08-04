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
public enum HJRPCId: Sendable, Equatable {
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

// MARK: - Codable

extension HJRPCId: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(value)
        } else if let value = try? container.decode(Double.self), value.rounded() == value {
            self = .number(Int(value))
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "The id is not a valid JSON-RPC identifier.")
        }
    }

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
