//
//  HJRPCRequestWrapper.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor
import HarborCore

/// Internal wrapper that adapts JSON-RPC requests to Harbor's request protocol.
struct HJRPCRequestWrapper<RawModel: HModel>: Sendable {
    /// The debug type to log with, or `nil` when the request did not opt into logging.
    let requestedDebugType: HDebugRequestType?
    /// The request object (`jsonrpc`, `method`, `id`, `params`).
    let jsonBody: [String: HJSONValue]
    /// The encoded body that is sent. `JSONEncoder` keeps big integers (`HJSONValue.decimal`) exact.
    let rawBody: Data?
    /// The id sent with the request, or `nil` for a notification.
    let jrpcID: HJRPCId?
    /// The endpoint the request is sent to.
    let url: String
    /// Whether the request needs auth.
    let needsAuth: Bool
    /// The retry policy of the JSON-RPC request.
    let retryPolicy: HRetryPolicy?
    /// The headers of the JSON-RPC request.
    let headerParameters: [String: String]?
    /// The timeout of the JSON-RPC request, or `nil` to use Harbor's default.
    let timeoutInterval: TimeInterval?
}

// MARK: - HJRPCTransportRequest

extension HJRPCRequestWrapper: HJRPCTransportRequest {
    /// The JSON-RPC response envelope wrapping the request's model.
    typealias Model = HJRPCResult<RawModel>

    /// The body as a dictionary, used by debug logs. The request itself is sent from `rawBody`.
    var bodyParameters: [String: Any]? {
        jsonBody.mapValues { $0.anyValue }
    }

    /// Decodes the response envelope. A notification answered with an empty (or whitespace-only)
    /// body decodes as an empty envelope, since the server MUST NOT reply to notifications
    /// (JSON-RPC 2.0, section 4.1); any other body must be a valid JSON-RPC response.
    func parseData<T: Codable>(data: Data, model: T.Type) throws -> T {
        if jrpcID == nil, data.isBlankJSONBody, let empty = HJRPCResult<RawModel>() as? T {
            return empty
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
