//
//  HRequestError.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import Network

/// Errors that can occur during network requests.
public enum HRequestError: Error, Sendable {
    /// API returned an error with status code and response data.
    case apiError(statusCode: Int, data: Data)
    /// Invalid HTTP response received.
    case invalidHttpResponse
    /// The request is invalid or malformed.
    case invalidRequest
    /// Authentication provider is required but not set.
    case authProviderNeeded
    /// Authentication is required for this request.
    case authNeeded
    /// Error occurred while encoding/decoding the model.
    case codableError(modelName: String, error: Error)
    /// No internet connection available.
    case noConnectionError
    /// The request is malformed and cannot be processed.
    case malformedRequestError
    /// Request timed out.
    case timeoutError
    /// Cannot find the specified host or connection failed.
    case cannotFindHost
    /// Request was cancelled.
    case cancelled
    /// SSL/TLS certificate validation failed.
    case sslError
    /// No cached data found for cache-only request.
    case noCachedDataFound
}

// MARK: - Error Description
extension HRequestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .apiError(let statusCode, _):
            return "API error with status code: \(statusCode)"
        case .invalidHttpResponse:
            return "Invalid HTTP response received"
        case .invalidRequest:
            return "Invalid request"
        case .authProviderNeeded:
            return "Authentication provider is required"
        case .authNeeded:
            return "Authentication is required"
        case .codableError(let modelName, let error):
            return "Failed to encode/decode \(modelName): \(error.localizedDescription)"
        case .noConnectionError:
            return "No internet connection available"
        case .malformedRequestError:
            return "Malformed request"
        case .timeoutError:
            return "Request timed out"
        case .cannotFindHost:
            return "Cannot find host or connection failed"
        case .cancelled:
            return "Request was cancelled"
        case .sslError:
            return "SSL/TLS certificate validation failed"
        case .noCachedDataFound:
            return "No cached data found"
        }
    }
}
