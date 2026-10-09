//
//  HJRPCBatchResponse.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

/// The result of a single request inside a JSON-RPC batch response.
public enum HJRPCBatchResponse: Sendable {
    /// The request completed successfully with its raw JSON result and the identifier echoed by the server.
    case success(id: HJRPCId?, result: HJSONValue)
    /// The request failed with an error and the identifier echoed by the server.
    case error(id: HJRPCId?, error: HJRPCRequestError)
}

// MARK: - Internal Batch Payload

/// The body of a response to a JSON-RPC batch.
enum HJRPCBatchPayload: HModel {
    /// An empty (or whitespace-only) body: the server's answer to a batch of notifications.
    case empty
    /// An array with one response object per answered request.
    case responses([HJRPCResult<HJSONValue>])
    /// A single response object, sent when the server rejects the batch as a whole
    /// (e.g. a parse error or an invalid batch, JSON-RPC 2.0 section 6).
    case single(HJRPCResult<HJSONValue>)

    /// Decodes an array of responses, or a single response object rejecting the whole batch.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let responses = try? container.decode([HJRPCResult<HJSONValue>].self) {
            self = .responses(responses)
        } else {
            self = .single(try container.decode(HJRPCResult<HJSONValue>.self))
        }
    }

    /// Encodes the payload back to its JSON form (used by mocks and tests).
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .empty:
            try container.encodeNil()
        case .responses(let responses):
            try container.encode(responses)
        case .single(let response):
            try container.encode(response)
        }
    }
}

// MARK: - Internal Batch Wrapper

/// Internal wrapper that adapts a JSON-RPC batch payload to Harbor's request protocol.
struct HJRPCBatchWrapper: HJRPCTransportRequest {
    /// The decoded batch response body.
    typealias Model = HJRPCBatchPayload

    /// The debug type to log with, or `nil` when no batched request opted into logging.
    let requestedDebugType: HDebugRequestType?
    /// The encoded batch array that is sent.
    let rawBody: Data?
    /// The ids of the batched requests, in order (`nil` for notifications).
    let requestIDs: [HJRPCId?]
    /// The endpoint shared by every batched request.
    let url: String
    /// Whether any batched request needs auth.
    let needsAuth: Bool
    /// The merged retry policy (see `HarborJRPC.batch(_:)`).
    let retryPolicy: HRetryPolicy?
    /// The merged headers of the batched requests.
    let headerParameters: [String: String]?

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
