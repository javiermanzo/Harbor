//
//  HJRPCBatchWrapper.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor
import HarborCore

/// Internal wrapper that adapts a JSON-RPC batch payload to Harbor's request protocol.
struct HJRPCBatchWrapper: Sendable {
    /// The debug type to log with, or `nil` when no batched request opted into logging.
    let requestedDebugType: HDebugRequestType?
    /// The encoded batch array that is sent.
    let rawBody: Data?
    /// The endpoint shared by every batched request.
    let url: String
    /// Whether any batched request needs auth.
    let needsAuth: Bool
    /// The merged retry policy (see `HarborJRPC.batch(_:)`).
    let retryPolicy: HRetryPolicy?
    /// The merged headers of the batched requests.
    let headerParameters: [String: String]?
    /// The longest timeout of the batched requests, or `nil` to use Harbor's default.
    let timeoutInterval: TimeInterval?
    /// The name debug logs show (e.g. `JSON-RPC batch (3 requests)`).
    let logName: String
}

// MARK: - HJRPCTransportRequest

extension HJRPCBatchWrapper: HJRPCTransportRequest {
    /// The decoded batch response body.
    typealias Model = HJRPCBatchPayload

    /// The batch is sent from `rawBody`; there are no dictionary body parameters.
    var bodyParameters: [String: Any]? { nil }

    /// Decodes the batch response. An empty (or whitespace-only) body decodes as `.empty`; any
    /// other body must be a JSON array of responses or a single response object.
    func parseData<T: Codable>(data: Data, model: T.Type) throws -> T {
        if data.isBlankJSONBody, let empty = HJRPCBatchPayload.empty as? T {
            return empty
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
