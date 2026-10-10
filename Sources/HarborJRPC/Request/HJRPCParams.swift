//
//  HJRPCParams.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation

/// Parameters of a JSON-RPC request.
///
/// The JSON-RPC 2.0 specification allows parameters to be structured either
/// by name (an object) or by position (an array).
public enum HJRPCParams: Sendable {
    /// Parameters structured by name, encoded as a JSON object.
    case named([String: any Encodable & Sendable])
    /// Parameters structured by position, encoded as a JSON array.
    case positioned([any Encodable & Sendable])
}

// MARK: - JSON Value Bridge

extension HJRPCParams {
    /// The parameters encoded as an `HJSONValue`.
    ///
    /// Each value is encoded with `JSONEncoder` and decoded back as an `HJSONValue`, so
    /// integers keep their exact digits (including `UInt64` values above `Int.max`) on iOS 18 /
    /// macOS 15 and later. On earlier OS versions the system `JSONDecoder` decodes such
    /// integers through `Double`, so they may be rounded (see `HJSONValue.decimal`).
    /// - Throws: The `EncodingError` raised for a value JSON cannot represent (e.g. `Double.nan`
    ///   or `Double.infinity`), instead of silently sending `null` in its slot.
    func jsonValue() throws -> HJSONValue {
        switch self {
        case .named(let parameters):
            return .object(try parameters.mapValues { try HJRPCParams.encodeToJSONValue($0) })
        case .positioned(let parameters):
            return .array(try parameters.map { try HJRPCParams.encodeToJSONValue($0) })
        }
    }

    /// Encodes one parameter and decodes it back as an `HJSONValue`.
    /// - Throws: The `EncodingError` raised for a value JSON cannot represent.
    private static func encodeToJSONValue(_ value: any Encodable & Sendable) throws -> HJSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(HJSONValue.self, from: data)
    }
}
