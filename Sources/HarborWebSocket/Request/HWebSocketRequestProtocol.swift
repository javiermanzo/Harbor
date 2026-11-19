//
//  HWebSocketRequestProtocol.swift
//  HarborWebSocket
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation
import HarborCore

// MARK: - HWebSocketRequestProtocol

/// A WebSocket endpoint. Conform a `Sendable` struct to it, set `url`, and call `connect()`.
///
/// The handshake goes through Harbor's pipeline: connectivity check, auth provider (with the
/// same `401` refresh flow as REST requests), default headers, retry policy, SSL pinning, mTLS
/// and custom session. The returned `HWebSocket` streams the messages and sends yours.
///
/// ```swift
/// struct ChatSocket: HWebSocketRequestProtocol {
///     let url = "wss://chat.example.com/rooms/{room}"
///     let pathParameters: [String: String]?
///     let needsAuth = true
///     let pingInterval: TimeInterval? = 30
///
///     init(room: String) {
///         pathParameters = ["room": room]
///     }
/// }
///
/// let socket = try await ChatSocket(room: "swift").connect()
/// try await socket.send("hello")
/// for try await message in socket.messages {
///     print(message)
/// }
/// await socket.close()
/// ```
public protocol HWebSocketRequestProtocol: Sendable {
    /// The endpoint URL. `ws` and `wss` schemes are expected; `http` and `https` are accepted
    /// and rewritten to `ws` and `wss`. Path parameters are written as `{name}`.
    var url: String { get }

    /// Values substituted into the `{name}` placeholders of `url`. Default: `nil`.
    var pathParameters: [String: String]? { get }

    /// Query items appended to the URL. Default: `nil`.
    var queryParameters: [String: String]? { get }

    /// Headers sent with the handshake, on top of `Harbor`'s default headers. Default: `nil`.
    var headerParameters: [String: String]? { get }

    /// Subprotocols offered in `Sec-WebSocket-Protocol`, in order of preference. The one the
    /// server selects is available as `HWebSocket.negotiatedSubprotocol`. Default: `[]`.
    var subprotocols: [String] { get }

    /// Whether the handshake needs the auth provider's header. Default: `false`.
    var needsAuth: Bool { get }

    /// Retry policy for the handshake (the connection itself is never reconnected). The
    /// handshake is treated as idempotent, so its `retryNonIdempotentRequests` does not
    /// apply. Default: `nil`, no retries.
    var retryPolicy: HRetryPolicy? { get }

    /// Timeout of the handshake in seconds. Default: `nil`, Harbor's default timeout
    /// (`Harbor.setDefaultTimeoutInterval(_:)`).
    var timeoutInterval: TimeInterval? { get }

    /// Interval between keep-alive pings, in seconds, sent regardless of traffic. A pong that
    /// does not arrive within the same interval closes the connection and the `messages`
    /// stream throws `HWebSocketError.pingTimeout`; the interval is also how long `ping()`
    /// waits. Default: `nil`, the interval set with `HarborWebSocket.setDefaultPingInterval(_:)`
    /// (no pings unless configured). Values that are not finite and greater than zero disable the pings.
    var pingInterval: TimeInterval? { get }

    /// Maximum size of a received message in bytes; a larger message closes the connection
    /// (`URLSession` sends close code 1009) and `messages` throws `.messageTooBig`.
    /// Default: `nil`, the system default (1 MiB). Values of 0 or less use the default too.
    var maximumMessageSize: Int? { get }

    /// Opens the connection.
    /// - Returns: The open connection.
    /// - Throws: An `HWebSocketError` when the handshake fails.
    func connect() async throws(HWebSocketError) -> HWebSocket
}

// MARK: - Default Implementations

/// Default property implementations for `HWebSocketRequestProtocol`.
public extension HWebSocketRequestProtocol {
    /// Default: `nil`, no path parameters.
    var pathParameters: [String: String]? { nil }
    /// Default: `nil`, no query items.
    var queryParameters: [String: String]? { nil }
    /// Default: `nil`, no additional headers.
    var headerParameters: [String: String]? { nil }
    /// Default: `[]`, no subprotocol is offered.
    var subprotocols: [String] { [] }
    /// Default: `false`, the handshake is sent without consulting the auth provider.
    var needsAuth: Bool { false }
    /// Default: `nil`, the handshake is not retried.
    var retryPolicy: HRetryPolicy? { nil }
    /// Default: `nil`, Harbor's default timeout.
    var timeoutInterval: TimeInterval? { nil }
    /// Default: `nil`, the interval set with `HarborWebSocket.setDefaultPingInterval(_:)`.
    var pingInterval: TimeInterval? { nil }
    /// Default: `nil`, the system default.
    var maximumMessageSize: Int? { nil }
}

// MARK: - Connecting

/// Default connection implementation.
public extension HWebSocketRequestProtocol {
    /// Opens the connection through `HWebSocketManager`.
    func connect() async throws(HWebSocketError) -> HWebSocket {
        try await HWebSocketManager.connect(request: self)
    }
}
