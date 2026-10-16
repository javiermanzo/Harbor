//
//  HWebSocketError.swift
//  HarborWebSocket
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation
import Harbor

/// The reason a WebSocket operation failed. Thrown by `connect()`, `send`, `ping()` and
/// `HWebSocketMessage.decode(_:)`, and by the `messages` stream when the connection is lost
/// without a close frame.
///
/// Transport failures mirror `HRequestError`; `.handshakeFailed`, `.notConnected`,
/// `.pingTimeout` and `.invalidURL` are specific to WebSocket connections.
public enum HWebSocketError: Sendable {
    /// The server answered the handshake with a status other than `101 Switching Protocols`
    /// (and other than `401`, which goes through the auth provider and ends in `.authNeeded`).
    case handshakeFailed(statusCode: Int)
    /// `send` or `ping()` was called on a connection that is already closed.
    case notConnected
    /// No pong answered a keep-alive ping within the ping interval; the connection was closed.
    case pingTimeout
    /// The server sent a message larger than `maximumMessageSize`; the connection was closed.
    case messageTooBig
    /// The URL could not be built, or its scheme is not `ws`, `wss`, `http` or `https`.
    case invalidURL(reason: String)
    /// A payload could not be encoded (`send(json:)`) or decoded (`HWebSocketMessage.decode(_:)`).
    case codable(modelName: String, error: Error)
    /// The request has `needsAuth` set but no provider was configured with `Harbor.setAuthProvider(_:)`.
    case authProviderNeeded
    /// The server rejected the credentials (`401`) and they could not be refreshed through
    /// `HAuthProviderProtocol.authFailed()`.
    case authNeeded
    /// The device is offline.
    case noConnection
    /// The handshake timed out.
    case timeout
    /// The host name could not be resolved.
    case cannotFindHost
    /// The host was resolved but a connection to it could not be established.
    case cannotConnectToHost
    /// The `Task` calling `connect()`, `send`, or `ping()` was cancelled. (Cancelling the task
    /// that iterates `messages` closes the connection instead: the stream finishes and `state`
    /// is `.closed(code: .goingAway, reason: nil)`.)
    case cancelled
    /// The TLS handshake failed: SSL pinning rejected the server, its certificate chain is
    /// invalid, or the client certificate was missing or rejected.
    case certificate
    /// A network error that does not map to a more specific case. Wraps the original `URLError`.
    case networkFailure(URLError)
    /// An unexpected error that is not a `URLError`, such as the POSIX error reported when a
    /// connection is dropped without a close frame. Wraps the original error.
    case unknown(Error)
}

// MARK: - HRequestError Mapping

extension HWebSocketError {
    /// Maps a transport error reported by Harbor's pipeline to a WebSocket error.
    /// - Parameter hRequestError: The error reported by Harbor.
    init(hRequestError: HRequestError) {
        switch hRequestError {
        case .api(let statusCode, _):
            self = .handshakeFailed(statusCode: statusCode)
        case .authProviderNeeded:
            self = .authProviderNeeded
        case .authNeeded:
            self = .authNeeded
        case .codable(let modelName, let error):
            self = .codable(modelName: modelName, error: error)
        case .noConnection:
            self = .noConnection
        case .malformedRequest(let reason):
            self = .invalidURL(reason: reason ?? "Malformed request")
        case .timeout:
            self = .timeout
        case .cannotFindHost:
            self = .cannotFindHost
        case .cannotConnectToHost:
            self = .cannotConnectToHost
        case .cancelled:
            self = .cancelled
        case .certificate:
            self = .certificate
        case .networkFailure(let error):
            self = .networkFailure(error)
        case .unknown(let error):
            self = .unknown(error)
        case .invalidHttpResponse, .noCachedDataFound:
            // Produced by REST responses and cache reads only, never by a WebSocket handshake.
            self = .unknown(hRequestError)
        }
    }
}

// MARK: - Error

extension HWebSocketError: Error {}

// MARK: - LocalizedError

extension HWebSocketError: LocalizedError {
    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .handshakeFailed(let statusCode):
            return "The WebSocket handshake failed with status code \(statusCode)."
        case .notConnected:
            return "The WebSocket connection is closed."
        case .pingTimeout:
            return "The server did not answer a keep-alive ping in time."
        case .messageTooBig:
            return "The server sent a message larger than the maximum message size."
        case .invalidURL(let reason):
            return "Invalid WebSocket URL: \(reason)"
        case .codable(let modelName, let error):
            return "Failed to encode or decode \(modelName): \(String(describing: error))"
        case .authProviderNeeded:
            return "An authentication provider is required but not set."
        case .authNeeded:
            return "Authentication is required for this connection."
        case .noConnection:
            return "No internet connection available."
        case .timeout:
            return "The WebSocket handshake timed out."
        case .cannotFindHost:
            return "Cannot find the specified host."
        case .cannotConnectToHost:
            return "Cannot connect to the specified host."
        case .cancelled:
            return "The WebSocket operation was cancelled."
        case .certificate:
            return "The SSL/TLS certificate validation failed."
        case .networkFailure(let error):
            return "Network request failed (\(error.code.rawValue)): \(error.localizedDescription)"
        case .unknown(let error):
            return "Unexpected error: \(String(describing: error))"
        }
    }
}

// MARK: - Equatable

extension HWebSocketError: Equatable {
    /// Two errors are equal when they are the same case with equal payloads. Wrapped errors
    /// that are not `Equatable` (`codable`, `unknown`) are compared by their type, bridged
    /// domain and code, and description; `networkFailure` compares the `URLError` codes.
    public static func == (lhs: HWebSocketError, rhs: HWebSocketError) -> Bool {
        switch (lhs, rhs) {
        case let (.handshakeFailed(lhsStatus), .handshakeFailed(rhsStatus)):
            return lhsStatus == rhsStatus
        case (.notConnected, .notConnected),
             (.pingTimeout, .pingTimeout),
             (.messageTooBig, .messageTooBig),
             (.authProviderNeeded, .authProviderNeeded),
             (.authNeeded, .authNeeded),
             (.noConnection, .noConnection),
             (.timeout, .timeout),
             (.cannotFindHost, .cannotFindHost),
             (.cannotConnectToHost, .cannotConnectToHost),
             (.cancelled, .cancelled),
             (.certificate, .certificate):
            return true
        case let (.invalidURL(lhsReason), .invalidURL(rhsReason)):
            return lhsReason == rhsReason
        case let (.codable(lhsModel, lhsError), .codable(rhsModel, rhsError)):
            return lhsModel == rhsModel && isSameError(lhsError, rhsError)
        case let (.networkFailure(lhsError), .networkFailure(rhsError)):
            return lhsError.code == rhsError.code
        case let (.unknown(lhsError), .unknown(rhsError)):
            return isSameError(lhsError, rhsError)
        default:
            return false
        }
    }

    /// Compares two arbitrary errors by dynamic type, bridged `NSError` domain and code, and description.
    private static func isSameError(_ lhs: Error, _ rhs: Error) -> Bool {
        let lhsNSError = lhs as NSError
        let rhsNSError = rhs as NSError
        return ObjectIdentifier(type(of: lhs)) == ObjectIdentifier(type(of: rhs))
            && lhsNSError.domain == rhsNSError.domain
            && lhsNSError.code == rhsNSError.code
            && String(describing: lhs) == String(describing: rhs)
    }
}
