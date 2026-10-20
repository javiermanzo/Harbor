//
//  HWebSocketError.swift
//  HarborWebSocket
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation
import HarborCore

/// The reason a WebSocket operation failed. Thrown by `connect()`, `send`, `ping()`,
/// `HWebSocketMessage.decode(_:)`, and by the `messages` stream when the connection is lost
/// without a close frame.
///
/// The cases follow the life of a connection rather than the HTTP request/response model:
/// the first group can only happen while the connection is being opened, the second one
/// once it is open (or when using a closed one).
public enum HWebSocketError: Sendable {
    // MARK: Opening the connection

    /// The URL could not be built, or its scheme is not `ws`, `wss`, `http` or `https`.
    case invalidURL(reason: String)
    /// The request has `needsAuth` set but no provider was configured with `Harbor.setAuthProvider(_:)`.
    case authProviderNeeded
    /// The server rejected the credentials (`401`) and they could not be refreshed through
    /// `HAuthProviderProtocol.authFailed()`.
    case authNeeded
    /// The server answered the handshake with a status other than `101 Switching Protocols`
    /// (and other than `401`, which goes through the auth provider and ends in `.authNeeded`).
    case handshakeFailed(statusCode: Int)
    /// The device is offline.
    case noConnection
    /// The handshake timed out.
    case timeout
    /// The host name could not be resolved.
    case cannotFindHost
    /// The host was resolved but a connection to it could not be established.
    case cannotConnectToHost
    /// The TLS handshake failed: SSL pinning rejected the server, its certificate chain is
    /// invalid, or the client certificate was missing or rejected.
    case certificate

    // MARK: Open connection

    /// `send` or `ping()` was called on a connection that is already closed.
    case notConnected
    /// No pong answered a keep-alive ping within the ping interval; the connection was closed.
    case pingTimeout
    /// The server sent a message larger than `maximumMessageSize`; the connection was closed.
    case messageTooBig
    /// The connection could not be opened or was lost without a close frame (for example the
    /// server went away), for a reason that has no more specific case. Wraps the `URLError`;
    /// when `URLSession` reported a POSIX error it is the `NSUnderlyingErrorKey` of a
    /// `.networkConnectionLost`.
    case connectionFailed(URLError)
    /// A value could not be encoded as JSON by `send(json:)`.
    case encodingFailed(modelName: String, error: Error)
    /// A message payload could not be decoded by `HWebSocketMessage.decode(_:)`.
    case decodingFailed(modelName: String, error: Error)

    // MARK: Any time

    /// The `Task` calling `connect()`, `send`, or `ping()` was cancelled. (Cancelling the task
    /// that iterates `messages` closes the connection instead: the stream finishes and `state`
    /// is `.closed(code: .goingAway, reason: nil)`.)
    case cancelled
    /// An unexpected error that is not a `URLError` nor a lost connection. Wraps the original error.
    case unknown(Error)
}

// MARK: - Mapping

extension HWebSocketError {
    /// Maps an error thrown by `URLSession` for a WebSocket task.
    /// - Parameters:
    ///   - urlError: The error.
    ///   - trustEvaluationFailed: Whether Harbor's delegate rejected a TLS challenge for the task.
    init(urlError: URLError, trustEvaluationFailed: Bool) {
        if trustEvaluationFailed {
            self = .certificate
            return
        }
        if urlError.code == .cancelled || Task.isCancelled {
            self = .cancelled
            return
        }
        switch urlError.code {
        case .badURL:
            self = .invalidURL(reason: urlError.localizedDescription)
        case .cannotFindHost, .dnsLookupFailed:
            self = .cannotFindHost
        case .cannotConnectToHost:
            self = .cannotConnectToHost
        case .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            self = .certificate
        case .timedOut:
            self = .timeout
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            self = .noConnection
        default:
            // Includes `.networkConnectionLost`: on an open connection that is a lost connection, not an offline device.
            self = .connectionFailed(urlError)
        }
    }

    /// Maps an error that is not a `URLError` thrown while using a WebSocket task.
    /// - Parameter error: The thrown error.
    init(otherError error: Error) {
        if error is CancellationError || Task.isCancelled {
            self = .cancelled
        } else if let lost = Self.lostConnectionError(error) {
            self = .connectionFailed(lost)
        } else {
            self = .unknown(error)
        }
    }

    /// `URLSession` reports a connection that dies under an open WebSocket as a POSIX error
    /// (`ENOTCONN`, `ECONNRESET`, `EPIPE`...) instead of a `URLError`. It is a lost connection,
    /// so it is reported as `networkConnectionLost` with the original error underneath.
    private static func lostConnectionError(_ error: Error) -> URLError? {
        let nsError = error as NSError
        guard nsError.domain == NSPOSIXErrorDomain else { return nil }
        let lost: Set<Int32> = [ENOTCONN, ECONNRESET, ECONNABORTED, EPIPE, ETIMEDOUT, ENETDOWN, ENETRESET, ENETUNREACH]
        guard lost.contains(Int32(truncatingIfNeeded: nsError.code)) else { return nil }
        return URLError(.networkConnectionLost, userInfo: [NSUnderlyingErrorKey: error])
    }

    /// Maps an error reported by Harbor's shared pipeline (authentication, URL building and
    /// the attempt loop) while opening a connection.
    /// - Parameter pipelineError: The error reported by `HarborCore`.
    init(pipelineError: HRequestError) {
        switch pipelineError {
        case .authProviderNeeded:
            self = .authProviderNeeded
        case .authNeeded:
            self = .authNeeded
        case .cancelled:
            self = .cancelled
        case .malformedRequest(let reason):
            self = .invalidURL(reason: reason ?? "Malformed request")
        case .api(let statusCode, _):
            self = .handshakeFailed(statusCode: statusCode)
        case .noConnection:
            self = .noConnection
        case .timeout:
            self = .timeout
        case .cannotFindHost:
            self = .cannotFindHost
        case .cannotConnectToHost:
            self = .cannotConnectToHost
        case .certificate:
            self = .certificate
        case .networkFailure(let urlError):
            self = .connectionFailed(urlError)
        case .unknown(let error):
            self = .unknown(error)
        case .invalidHttpResponse, .codable, .noCachedDataFound:
            // Produced by REST responses and cache reads only, never while opening a connection.
            self = .unknown(pipelineError)
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
        case .encodingFailed(let modelName, let error):
            return "Failed to encode \(modelName): \(String(describing: error))"
        case .decodingFailed(let modelName, let error):
            return "Failed to decode \(modelName): \(String(describing: error))"
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
        case .connectionFailed(let error):
            return "The WebSocket connection failed (\(error.code.rawValue)): \(error.localizedDescription)"
        case .unknown(let error):
            return "Unexpected error: \(String(describing: error))"
        }
    }
}

// MARK: - Equatable

extension HWebSocketError: Equatable {
    /// Two errors are equal when they are the same case with equal payloads. Wrapped errors
    /// that are not `Equatable` (`encodingFailed`, `decodingFailed`, `unknown`) are compared by their type,
    /// bridged domain and code, and description; `connectionFailed` compares the `URLError` codes.
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
        case let (.encodingFailed(lhsModel, lhsError), .encodingFailed(rhsModel, rhsError)),
             let (.decodingFailed(lhsModel, lhsError), .decodingFailed(rhsModel, rhsError)):
            return lhsModel == rhsModel && isSameError(lhsError, rhsError)
        case let (.connectionFailed(lhsError), .connectionFailed(rhsError)):
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
