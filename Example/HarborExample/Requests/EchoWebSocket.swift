//
//  EchoWebSocket.swift
//  HarborExample
//
//  WebSocket demo against a public echo service
//

import Foundation
import Harbor
import HarborWebSocket

/// Connects to a public echo server: every message sent is echoed back. The connection goes
/// through Harbor's pipeline (default headers, auth provider, pinning, mTLS, logging), keeps
/// itself alive with a ping every 20 seconds and logs the handshake and the messages.
struct EchoWebSocket: HWebSocketRequestProtocol, HDebugRequestProtocol {
    let url = "wss://echo.websocket.org"
    let timeoutInterval: TimeInterval? = 10
    let pingInterval: TimeInterval? = 20
    // Only the handshake is retried: an open connection is never reconnected automatically.
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 2)
    let debugType: HDebugRequestType = .requestAndResponse
}

/// A JSON payload sent through the socket with `send(json:)` and decoded back with `decode(_:)`.
struct EchoPayload: Codable, Sendable {
    let id: Int
    let text: String
}
