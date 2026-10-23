//
//  HJRPCBatchResponse.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation

/// The result of a single request inside a JSON-RPC batch response.
public enum HJRPCBatchResponse: Sendable {
    /// The request completed successfully with its raw JSON result and the identifier echoed by the server.
    case success(id: HJRPCId?, result: HJSONValue)
    /// The request failed with an error and the identifier echoed by the server (or, for a request
    /// the server did not answer, the identifier it was sent with).
    case error(id: HJRPCId?, error: HJRPCRequestError)
}

// MARK: - Identifier

public extension HJRPCBatchResponse {
    /// The identifier of the element: the `id` echoed by the server, or the one the request was
    /// sent with when the server did not answer it. `nil` when the element carries no `id`.
    var id: HJRPCId? {
        switch self {
        case .success(let id, _), .error(let id, _):
            return id
        }
    }
}

// MARK: - Equatable

extension HJRPCBatchResponse: Equatable {}
