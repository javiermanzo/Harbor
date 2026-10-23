//
//  HJRPCRequestError.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor
import HarborCore

/// The reason a JSON-RPC call failed. Thrown by `request()`, `notify()` and `HarborJRPC.batch(_:)`,
/// and returned in `HJRPCResponse.error` by `requestResult()`.
///
/// Transport failures mirror `HRequestError`; `.jrpcError`, `.invalidResponse`, `.idMismatch`,
/// `.urlNeeded` and `.invalidRequest` are specific to JSON-RPC.
public enum HJRPCRequestError: Sendable {
    /// The server answered with a non-2xx status code and a body that is not a JSON-RPC error
    /// object. Carries the status code and the response body.
    case api(statusCode: Int, data: Data)
    /// The server returned a JSON-RPC error object (with any HTTP status; see `HJRPCError.httpStatusCode`).
    case jrpcError(error: HJRPCError)
    /// No endpoint: `HarborJRPC.configure(url:jrpcVersion:)` was not called and the request has no `endpoint`.
    case urlNeeded
    /// Invalid HTTP response received.
    case invalidHttpResponse
    /// `notify()` was called on a request whose `isNotification` is `false`, or `request()` /
    /// `requestResult()` on one whose `isNotification` is `true`. Nothing was sent.
    case invalidRequest
    /// The server response is not a valid JSON-RPC response.
    case invalidResponse
    /// The response identifier does not match the request identifier.
    case idMismatch(expected: HJRPCId?, actual: HJRPCId?)
    /// The request has `needsAuth` set but no provider was configured with `Harbor.setAuthProvider(_:)`.
    case authProviderNeeded
    /// The server answered `401` and the credentials could not be refreshed (or the request has
    /// no `needsAuth`). A JSON-RPC error object in a `401` body is not decoded.
    case authNeeded
    /// Error occurred while encoding/decoding the model.
    case codable(modelName: String, error: Error)
    /// No internet connection available.
    case noConnection
    /// The request is malformed and cannot be processed. The reason describes what failed.
    case malformedRequest(reason: String? = nil)
    /// Request timed out.
    case timeout
    /// The host name could not be resolved.
    case cannotFindHost
    /// The host was resolved but a connection to it could not be established.
    case cannotConnectToHost
    /// SSL/TLS certificate validation failed.
    case certificate
    /// Request was cancelled.
    case cancelled
    /// A network error that does not map to a more specific case. Wraps the original `URLError`.
    case networkFailure(URLError)
    /// An unexpected error that is not a `URLError`. Wraps the original error.
    case unknown(Error)
}

// MARK: - Mapping

extension HJRPCRequestError {
    /// Maps an `HRequestError` to an `HJRPCRequestError`.
    /// - Parameter hRequestError: The transport error reported by Harbor for the underlying HTTP request.
    static func getError(hRequestError: HRequestError) -> HJRPCRequestError {
        switch hRequestError {
        case .api(let statusCode, let data):
            return .api(statusCode: statusCode, data: data)
        case .invalidHttpResponse:
            return .invalidHttpResponse
        case .authProviderNeeded:
            return .authProviderNeeded
        case .authNeeded:
            return .authNeeded
        case .codable(let modelName, let error):
            return .codable(modelName: modelName, error: error)
        case .noConnection:
            return .noConnection
        case .malformedRequest(let reason):
            return .malformedRequest(reason: reason)
        case .timeout:
            return .timeout
        case .cannotFindHost:
            return .cannotFindHost
        case .cannotConnectToHost:
            return .cannotConnectToHost
        case .cancelled:
            return .cancelled
        case .certificate:
            return .certificate
        case .noCachedDataFound:
            // Only produced by cache reads of GET requests, never by a JSON-RPC call.
            return .unknown(hRequestError)
        case .networkFailure(let error):
            return .networkFailure(error)
        case .unknown(let error):
            return .unknown(error)
        }
    }
}

// MARK: - Error

extension HJRPCRequestError: Error {}

// MARK: - LocalizedError

extension HJRPCRequestError: LocalizedError {
    /// Maximum number of characters of the response body included in an `.api` description.
    private static let bodyPreviewLimit = 500

    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .api(let statusCode, let data):
            let description = "The API returned an error with status code \(statusCode)."
            guard !data.isEmpty else { return description }
            // Redacted like `HRequestError.api` and debug logs: sensitive fields are masked
            // before the preview is cut.
            return description + " Body: \(HRedactionPolicy.current.bodyPreview(data, limit: Self.bodyPreviewLimit))"
        case .jrpcError(let error):
            return "JSON-RPC error \(error.code): \(error.message)"
        case .urlNeeded:
            return "The JSON-RPC URL is not set. Configure it with HarborJRPC.configure(url:jrpcVersion:)."
        case .invalidHttpResponse:
            return "The server returned an invalid HTTP response."
        case .invalidRequest:
            return "The request's isNotification does not match the call: send notifications with notify() and other requests with request() or requestResult()."
        case .invalidResponse:
            return "The server response is not a valid JSON-RPC response."
        case .idMismatch(let expected, let actual):
            let expectedDescription = expected?.description ?? "none"
            let actualDescription = actual?.description ?? "none"
            return "The response id (\(actualDescription)) does not match the request id (\(expectedDescription))."
        case .authProviderNeeded:
            return "An authentication provider is required but not set."
        case .authNeeded:
            return "Authentication is required for this request."
        case .codable(let modelName, let error):
            return "Failed to encode or decode the model \(modelName): \(String(describing: error))"
        case .noConnection:
            return "No internet connection available."
        case .malformedRequest(let reason):
            return reason.map { "The request is malformed: \($0)" } ?? "The request is malformed and cannot be processed."
        case .timeout:
            return "The request timed out."
        case .cannotFindHost:
            return "Cannot find the specified host."
        case .cannotConnectToHost:
            return "Cannot connect to the specified host."
        case .certificate:
            return "The SSL/TLS certificate validation failed."
        case .cancelled:
            return "The request was cancelled."
        case .networkFailure(let error):
            return "Network request failed (\(error.code.rawValue)): \(error.localizedDescription)"
        case .unknown(let error):
            return "Unexpected error: \(String(describing: error))"
        }
    }
}

// MARK: - Equatable

extension HJRPCRequestError: Equatable {
    /// Two errors are equal when they are the same case with equal payloads. Wrapped errors
    /// that are not `Equatable` (`codable`, `unknown`) are compared by their type, bridged
    /// domain and code, and description; `networkFailure` compares the `URLError` codes.
    public static func == (lhs: HJRPCRequestError, rhs: HJRPCRequestError) -> Bool {
        switch (lhs, rhs) {
        case let (.api(lhsStatus, lhsData), .api(rhsStatus, rhsData)):
            return lhsStatus == rhsStatus && lhsData == rhsData
        case let (.jrpcError(lhsError), .jrpcError(rhsError)):
            return lhsError == rhsError
        case let (.idMismatch(lhsExpected, lhsActual), .idMismatch(rhsExpected, rhsActual)):
            return lhsExpected == rhsExpected && lhsActual == rhsActual
        case (.urlNeeded, .urlNeeded),
             (.invalidHttpResponse, .invalidHttpResponse),
             (.invalidRequest, .invalidRequest),
             (.invalidResponse, .invalidResponse),
             (.authProviderNeeded, .authProviderNeeded),
             (.authNeeded, .authNeeded),
             (.noConnection, .noConnection),
             (.timeout, .timeout),
             (.cannotFindHost, .cannotFindHost),
             (.cannotConnectToHost, .cannotConnectToHost),
             (.certificate, .certificate),
             (.cancelled, .cancelled):
            return true
        case let (.codable(lhsModel, lhsError), .codable(rhsModel, rhsError)):
            return lhsModel == rhsModel && HRequestError.isSameError(lhsError, rhsError)
        case let (.malformedRequest(lhsReason), .malformedRequest(rhsReason)):
            return lhsReason == rhsReason
        case let (.networkFailure(lhsError), .networkFailure(rhsError)):
            return lhsError.code == rhsError.code
        case let (.unknown(lhsError), .unknown(rhsError)):
            return HRequestError.isSameError(lhsError, rhsError)
        default:
            return false
        }
    }
}
