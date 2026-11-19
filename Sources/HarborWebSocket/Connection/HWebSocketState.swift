//
//  HWebSocketState.swift
//  HarborWebSocket
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation

/// The lifecycle state of an `HWebSocket`. A connection returned by `connect()` starts
/// `.open` and becomes `.closed` exactly once.
public enum HWebSocketState: Sendable {
    /// The connection is open: messages can be sent and received.
    case open
    /// The connection is closed. `code` is the close code of the close frame (sent by the
    /// server, or by `close(code:reason:)`), or `.abnormalClosure` when the connection was
    /// lost without a close frame (in that case the `messages` stream throws the reason).
    case closed(code: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

// MARK: - Equatable

extension HWebSocketState: Equatable {}
