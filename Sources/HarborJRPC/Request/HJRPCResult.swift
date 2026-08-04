//
//  HJRPCResult.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

/// A JSON-RPC 2.0 response envelope.
///
/// A JSON-RPC response contains either a `result` or an `error` member, never both.
/// The `result` member may also be present with an explicit `null` value.
public struct HJRPCResult<Model: HModel>: HModel {
    /// The JSON-RPC protocol version declared by the server.
    public let jsonrpc: String?
    /// The identifier of the request this response belongs to.
    public let id: HJRPCId?
    /// The result of a successful call. `nil` when the call failed or the result is `null`.
    public let result: Model?
    /// The error of a failed call.
    public let error: HJRPCError?

    /// Whether the response contains a `result` member.
    var hasResult: Bool
    /// Whether the response contains a `result` member with an explicit `null` value.
    var resultIsNull: Bool

    /// Creates a new JSON-RPC response envelope.
    /// - Parameters:
    ///   - jsonrpc: The JSON-RPC protocol version.
    ///   - id: The request identifier.
    ///   - result: The result of the call.
    ///   - error: The error of the call.
    public init(jsonrpc: String? = nil, id: HJRPCId? = nil, result: Model? = nil, error: HJRPCError? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
        self.hasResult = result != nil
        self.resultIsNull = false
    }
}

// MARK: - Decodable

extension HJRPCResult {
    private enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case result
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        jsonrpc = try container.decodeIfPresent(String.self, forKey: .jsonrpc)
        id = try container.decodeIfPresent(HJRPCId.self, forKey: .id)
        error = try container.decodeIfPresent(HJRPCError.self, forKey: .error)
        hasResult = container.contains(.result)
        resultIsNull = try hasResult && container.decodeNil(forKey: .result)
        result = try container.decodeIfPresent(Model.self, forKey: .result)
    }
}
