//
//  HarborWebSocket.swift
//  HarborWebSocket
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation
import HarborCore

/// Entry point of the HarborWebSocket module: global WebSocket configuration.
///
/// Network-level settings (timeouts, auth provider, default headers, mTLS, SSL pinning, custom
/// session, logging) are shared with REST requests and configured through `Harbor`. Connections
/// are opened from a `HWebSocketRequestProtocol` conformer:
///
/// ```swift
/// struct ChatSocket: HWebSocketRequestProtocol {
///     let url = "wss://chat.example.com/socket"
/// }
///
/// let socket = try await ChatSocket().connect()
/// try await socket.send("hello")
/// for try await message in socket.messages {
///     print(message)
/// }
/// ```
@HRequestManagerActor
public enum HarborWebSocket {

    /// Sets the keep-alive ping interval applied to connections whose request leaves
    /// `pingInterval` as `nil`. Default: `nil`, no keep-alive pings are sent.
    ///
    /// While set, every connection sends a ping frame every `interval` seconds, regardless of
    /// traffic, and closes itself (the `messages` stream throws `HWebSocketError.pingTimeout`)
    /// when the pong does not arrive within the same interval. Values that are not finite and
    /// greater than zero disable the pings.
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    /// - Parameter interval: The interval between pings in seconds, or `nil` to disable them.
    public static func setDefaultPingInterval(_ interval: TimeInterval?) {
        HWebSocketConfig.shared.pingInterval = interval
    }
}
