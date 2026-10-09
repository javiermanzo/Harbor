//
//  HRequestError.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import Network

/// The reason a request failed. Returned in `HResponse.error` and `HResponseWithResult.error`
/// (REST requests never throw) and thrown by `requestStream(source:)`.
public enum HRequestError: Error, Sendable {
    /// The server answered with a non-2xx status code. Carries the status code and the response body.
    case api(statusCode: Int, data: Data)
    /// Invalid HTTP response received.
    case invalidHttpResponse
    /// The request has `needsAuth` set but no provider was configured with `Harbor.setAuthProvider(_:)`.
    case authProviderNeeded
    /// The server rejected the credentials (`401`) and they could not be refreshed through
    /// `HAuthProviderProtocol.authFailed()`.
    case authNeeded
    /// The response body could not be decoded into the model, or a body could not be encoded.
    case codable(modelName: String, error: Error)
    /// The device is offline (and no usable cached response was found for a GET request).
    case noConnection
    /// The request is malformed and cannot be processed. The reason describes what failed.
    case malformedRequest(reason: String? = nil)
    /// Request timed out.
    case timeout
    /// The host name could not be resolved.
    case cannotFindHost
    /// The host was resolved but a connection to it could not be established.
    case cannotConnectToHost
    /// The request was cancelled, e.g. because its `Task` was cancelled.
    case cancelled
    /// The TLS handshake failed: SSL pinning rejected the server, its certificate chain is
    /// invalid, or the client certificate was missing or rejected.
    case certificate
    /// `requestStream(source: .cacheOnly)` found no usable cached response.
    case noCachedDataFound
    /// A network error that does not map to a more specific case. Wraps the original `URLError`.
    case networkFailure(URLError)
    /// An unexpected error that is not a `URLError`. Wraps the original error.
    case unknown(Error)
}

// MARK: - URLError Mapping
extension HRequestError {
    /// Maximum number of characters of a response body included in error descriptions.
    private static let bodyPreviewLimit = 500

    /// Maps a raw `URLError` to a strongly typed `HRequestError`.
    ///
    /// Only certificate-specific codes map to `.certificate` (an untrusted, expired, not yet
    /// valid or unknown-root server certificate; a missing or rejected client certificate).
    /// `.secureConnectionFailed` is a generic TLS failure (a dropped handshake, a protocol
    /// mismatch, a middlebox reset) and is reported as `.networkFailure`, so it can be retried
    /// like a lost connection.
    /// - Parameter error: The `URLError` thrown by `URLSession`.
    static func mapURLError(_ error: URLError) -> HRequestError {
        switch error.code {
        case .cancelled:
            return .cancelled
        case .badURL:
            return .malformedRequest(reason: "Invalid URL: \(error.localizedDescription)")
        case .cannotFindHost, .dnsLookupFailed:
            return .cannotFindHost
        case .cannotConnectToHost:
            return .cannotConnectToHost
        case .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return .certificate
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .noConnection
        case .resourceUnavailable:
            return .invalidHttpResponse
        default:
            return .networkFailure(error)
        }
    }
}

// MARK: - Error Description
extension HRequestError: LocalizedError {
    /// A human-readable description of the error. The body preview of `.api` is redacted with
    /// the same policy as debug logs (see `Harbor.setLogSensitiveValues(_:)`).
    public var errorDescription: String? {
        switch self {
        case .api(let statusCode, let data):
            var description = "API error with status code: \(statusCode)"
            guard !data.isEmpty else { return description }
            // Same redaction policy as debug logs: sensitive JSON fields (e.g. `access_token`)
            // and form fields are redacted before the preview is cut, and a JSON-like body
            // that cannot be parsed is omitted rather than printed raw.
            description += ", body: \(HRedactionPolicy.current.bodyPreview(data, limit: Self.bodyPreviewLimit))"
            return description
        case .invalidHttpResponse:
            return "Invalid HTTP response received"
        case .authProviderNeeded:
            return "Authentication provider is required"
        case .authNeeded:
            return "Authentication is required"
        case .codable(let modelName, let error):
            return "Failed to encode/decode \(modelName): \(String(describing: error))"
        case .noConnection:
            return "No internet connection available"
        case .malformedRequest(let reason):
            return reason.map { "Malformed request: \($0)" } ?? "Malformed request"
        case .timeout:
            return "Request timed out"
        case .cannotFindHost:
            return "Cannot find host"
        case .cannotConnectToHost:
            return "Cannot connect to host"
        case .cancelled:
            return "Request was cancelled"
        case .certificate:
            return "SSL/TLS certificate validation failed"
        case .noCachedDataFound:
            return "No cached data found"
        case .networkFailure(let error):
            return "Network request failed (\(error.code.rawValue)): \(error.localizedDescription)"
        case .unknown(let error):
            return "Unexpected error: \(String(describing: error))"
        }
    }
}

// MARK: - Equatable
extension HRequestError: Equatable {
    /// Two errors are equal when they are the same case with equal payloads. Wrapped errors
    /// that are not `Equatable` (`codable`, `unknown`) are compared by their type, bridged
    /// domain and code, and description; `networkFailure` compares the `URLError` codes.
    public static func == (lhs: HRequestError, rhs: HRequestError) -> Bool {
        switch (lhs, rhs) {
        case let (.api(lhsStatus, lhsData), .api(rhsStatus, rhsData)):
            return lhsStatus == rhsStatus && lhsData == rhsData
        case (.invalidHttpResponse, .invalidHttpResponse),
             (.authProviderNeeded, .authProviderNeeded),
             (.authNeeded, .authNeeded),
             (.noConnection, .noConnection),
             (.timeout, .timeout),
             (.cannotFindHost, .cannotFindHost),
             (.cannotConnectToHost, .cannotConnectToHost),
             (.cancelled, .cancelled),
             (.certificate, .certificate),
             (.noCachedDataFound, .noCachedDataFound):
            return true
        case let (.codable(lhsModel, lhsError), .codable(rhsModel, rhsError)):
            return lhsModel == rhsModel && isSameError(lhsError, rhsError)
        case let (.malformedRequest(lhsReason), .malformedRequest(rhsReason)):
            return lhsReason == rhsReason
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
