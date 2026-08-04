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
    /// Each value is encoded with `JSONEncoder` and converted to `HJSONValue`.
    /// A value that fails to encode is represented as `.null` in its slot.
    var jsonValue: HJSONValue {
        switch self {
        case .named(let parameters):
            return .object(parameters.mapValues { HJRPCParams.encodeToJSONValue($0) })
        case .positioned(let parameters):
            return .array(parameters.map { HJRPCParams.encodeToJSONValue($0) })
        }
    }

    private static func encodeToJSONValue(_ value: any Encodable & Sendable) -> HJSONValue {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]),
              let jsonValue = HJSONValue(anyValue: object) else {
            return .null
        }
        return jsonValue
    }
}
