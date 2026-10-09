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
struct HJRPCResult<Model: HModel>: HModel {
    /// The JSON-RPC protocol version declared by the server.
    let jsonrpc: String?
    /// The identifier of the request this response belongs to.
    let id: HJRPCId?
    /// The result of a successful call. `nil` when the call failed or the result is `null`.
    let result: Model?
    /// The error of a failed call.
    let error: HJRPCError?

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
    init(jsonrpc: String? = nil, id: HJRPCId? = nil, result: Model? = nil, error: HJRPCError? = nil) {
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
    /// The members of a JSON-RPC response object.
    private enum CodingKeys: String, CodingKey {
        /// The `jsonrpc` member.
        case jsonrpc
        /// The `id` member.
        case id
        /// The `result` member.
        case result
        /// The `error` member.
        case error
    }

    /// Decodes the envelope, recording whether `result` is present and whether it is an explicit `null`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        jsonrpc = try container.decodeIfPresent(String.self, forKey: .jsonrpc)
        id = try container.decodeIfPresent(HJRPCId.self, forKey: .id)
        error = try container.decodeIfPresent(HJRPCError.self, forKey: .error)
        hasResult = container.contains(.result)
        resultIsNull = try hasResult && container.decodeNil(forKey: .result)
        result = try container.decodeIfPresent(Model.self, forKey: .result)
    }
}
