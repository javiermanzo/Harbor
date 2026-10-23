//
//  HJRPCBatchPayload.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation

/// The body of a response to a JSON-RPC batch.
enum HJRPCBatchPayload: Sendable {
    /// An empty (or whitespace-only) body: the server's answer to a batch of notifications.
    case empty
    /// An array with one element per answered request.
    case responses([Element])
    /// A single response object, sent when the server rejects the batch as a whole
    /// (e.g. a parse error or an invalid batch, JSON-RPC 2.0 section 6).
    case single(HJRPCResult<HJSONValue>)
}

// MARK: - Element

extension HJRPCBatchPayload {
    /// One element of a batch response array. An element that is not a valid response object
    /// is kept apart instead of failing the whole batch, so the other elements are still delivered.
    enum Element: Sendable {
        /// A response object.
        case response(HJRPCResult<HJSONValue>)
        /// A value that is not a valid response object, with its `id` when one could be read.
        case malformed(id: HJRPCId?)
    }
}

// MARK: - Codable

extension HJRPCBatchPayload: Codable {
    /// Decodes an array of responses, or a single response object rejecting the whole batch.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let elements = try? container.decode([Element].self) {
            self = .responses(elements)
        } else {
            self = .single(try container.decode(HJRPCResult<HJSONValue>.self))
        }
    }

    /// Encodes the payload back to its JSON form. Required by `HModel` (`Codable`); Harbor only decodes it.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .empty:
            try container.encodeNil()
        case .responses(let elements):
            try container.encode(elements)
        case .single(let response):
            try container.encode(response)
        }
    }
}

// MARK: - Codable

extension HJRPCBatchPayload.Element: Codable {
    /// Decodes a response object, or records the element as malformed (never throws for a
    /// valid JSON value, so one bad element cannot fail the batch).
    init(from decoder: Decoder) throws {
        if let response = try? HJRPCResult<HJSONValue>(from: decoder) {
            self = .response(response)
            return
        }
        guard case .object(let members)? = try? HJSONValue(from: decoder),
              let idValue = members["id"] else {
            self = .malformed(id: nil)
            return
        }
        switch idValue {
        case .string(let value):
            self = .malformed(id: .string(value))
        case .int(let value):
            self = .malformed(id: .number(value))
        case .null:
            self = .malformed(id: .null)
        default:
            self = .malformed(id: nil)
        }
    }

    /// Encodes a response object, or an object with only the `id` of a malformed element.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .response(let response):
            try container.encode(response)
        case .malformed(let id):
            try container.encode(["id": id ?? .null])
        }
    }
}
