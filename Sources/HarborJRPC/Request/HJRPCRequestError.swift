//
//  HJRPCRequestError.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

/// Errors that can occur during JSON-RPC requests.
public enum HJRPCRequestError: Error, Sendable {
    /// API returned an error with status code and response data.
    case api(statusCode: Int, data: Data)
    /// JSON-RPC specific error returned by the server.
    case jrpcError(error: HJRPCError)
    /// Base URL is required but not set.
    case urlNeeded
    /// Invalid HTTP response received.
    case invalidHttpResponse
    /// The request is invalid or malformed.
    case invalidRequest
    /// The server response is not a valid JSON-RPC response.
    case invalidResponse
    /// The response identifier does not match the request identifier.
    case idMismatch(expected: HJRPCId?, actual: HJRPCId?)
    /// Authentication provider is required but not set.
    case authProviderNeeded
    /// Authentication is required for this request.
    case authNeeded
    /// Error occurred while encoding/decoding the model.
    case codable(modelName: String, error: Error)
    /// No internet connection available.
    case noConnection
    /// The request is malformed and cannot be processed. The reason describes what failed.
    case malformedRequest(reason: String? = nil)
    /// Request timed out.
    case timeout
    /// Cannot find the specified host.
    case cannotFindHost
    /// SSL/TLS certificate validation failed.
    case certificate
    /// Request was cancelled.
    case cancelled
    /// No cached data found for cache-only request.
    case noCachedDataFound
    /// A network error that does not map to a more specific case. Wraps the original `URLError`.
    case networkFailure(URLError)
}

extension HJRPCRequestError {
    /// Maps an `HRequestError` to an `HJRPCRequestError`.
    /// - Parameter hRequestError: The hRequestError.
    static func getError(hRequestError: HRequestError) -> HJRPCRequestError {
        switch hRequestError {
        case .api(let statusCode, let data):
            return .api(statusCode: statusCode, data: data)
        case .invalidHttpResponse:
            return .invalidHttpResponse
        case .invalidRequest:
            return .invalidRequest
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
        case .cancelled:
            return .cancelled
        case .certificate:
            return .certificate
        case .noCachedDataFound:
            return .noCachedDataFound
        case .networkFailure(let error):
            return .networkFailure(error)
        }
    }
}

// MARK: - LocalizedError

extension HJRPCRequestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .api(let statusCode, _):
            return "The API returned an error with status code \(statusCode)."
        case .jrpcError(let error):
            return "JSON-RPC error \(error.code): \(error.message)"
        case .urlNeeded:
            return "The JSON-RPC URL is not set. Configure it with HarborJRPC.setURL(_:) or HarborJRPC.configure(url:jrpcVersion:)."
        case .invalidHttpResponse:
            return "The server returned an invalid HTTP response."
        case .invalidRequest:
            return "The request is invalid or malformed."
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
            return "Failed to encode or decode the model \(modelName): \(error.localizedDescription)"
        case .noConnection:
            return "No internet connection available."
        case .malformedRequest(let reason):
            return reason.map { "The request is malformed: \($0)" } ?? "The request is malformed and cannot be processed."
        case .timeout:
            return "The request timed out."
        case .cannotFindHost:
            return "Cannot find the specified host."
        case .certificate:
            return "The SSL/TLS certificate validation failed."
        case .cancelled:
            return "The request was cancelled."
        case .noCachedDataFound:
            return "No cached data found for a cache-only request."
        case .networkFailure(let error):
            return "Network request failed (\(error.code.rawValue)): \(error.localizedDescription)"
        }
    }
}
