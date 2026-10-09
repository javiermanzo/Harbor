//
//  HarborJRPC.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

/// Entry point of the HarborJRPC module: global JSON-RPC configuration and batch calls.
///
/// Network-level settings (timeouts, auth provider, mTLS, SSL pinning, mocks, logging) are
/// shared with REST requests and configured through `Harbor`.
///
/// ```swift
/// await HarborJRPC.configure(url: URL(string: "https://rpc.example.com")!)
/// let block = try await BlockNumberRequest().request()
/// ```
@HRequestManagerActor
public enum HarborJRPC {

    /// Sets the endpoint every JSON-RPC request is sent to (unless the request overrides
    /// `endpoint`) and the protocol version sent in the `jsonrpc` member.
    /// - Parameters:
    ///   - url: The JSON-RPC endpoint.
    ///   - jrpcVersion: The JSON-RPC version string sent with every request and expected in every
    ///     response. Default: `"2.0"`.
    public static func configure(url: URL, jrpcVersion: String = "2.0") {
        HJRPCRequestManager.config = HJRPCConfig(url: url.absoluteString, jrpcVersion: jrpcVersion)
    }

    /// Sends several JSON-RPC requests as a single batch call (JSON-RPC 2.0, section 6).
    ///
    /// Notifications included in the batch do not produce a response element.
    /// Servers may reorder or omit responses, so each response is paired with the identifier echoed by the server.
    /// The requests share one HTTP request: they must target the same endpoint, their headers are
    /// merged (the first request setting a header wins), and the first non-nil retry policy is used.
    /// The batch is authenticated when any request has `needsAuth`, and logged when any request
    /// conforms to `HDebugRequestProtocol`. Since a batch is a `POST` that may contain writes, the
    /// retry policy's `retryNonIdempotentRequests` is only kept when every request in the batch
    /// opts in.
    /// - Parameter requests: The requests to send in the batch. An empty array returns `[]` without a network call.
    /// - Returns: One `HJRPCBatchResponse` per response element returned by the server.
    /// - Throws: An `HJRPCRequestError` when the batch as a whole fails (no endpoint, transport or
    ///   HTTP error, an invalid response body, or a JSON-RPC error rejecting the whole batch).
    public static func batch(_ requests: [any HJRPCRequestProtocol]) async throws -> [HJRPCBatchResponse] {
        try await HJRPCRequestManager.batch(requests: requests)
    }
}
