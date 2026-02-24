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
    case api(statusCode: Int, data: Data)
    /// Invalid HTTP response received.
    case invalidHttpResponse
    /// The request is invalid or malformed.
    case invalidRequest
    /// Authentication provider is required but not set.
    case authProviderNeeded
    /// Authentication is required for this request.
    case authNeeded
    /// Error occurred while encoding/decoding the model.
    case codable(modelName: String, error: Error)
    /// No internet connection available.
    case noConnection
    /// The request is malformed and cannot be processed.
    case malformedRequest
    /// Request timed out.
    case timeout
    /// Cannot find the specified host or connection failed.
    case cannotFindHost
    /// Request was cancelled.
    case cancelled
    /// SSL/TLS certificate validation failed.
    case certificate
    /// No cached data found for cache-only request.
    case noCachedDataFound
}

// MARK: - Error Description
extension HRequestError: LocalizedError {
    static func mapURLError(_ error: URLError) -> HRequestError {
        switch error.code {
        case .cancelled:
            return .cancelled
        case .badURL:
            return .malformedRequest
        case .cannotConnectToHost:
            return .cannotFindHost
        case .serverCertificateUntrusted:
            return .certificate
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost:
            return .noConnection
        case .cannotFindHost:
            return .cannotFindHost
        default:
            return .invalidHttpResponse
        }
    }

    public var errorDescription: String? {
        switch self {
        case .api(let statusCode, _):
            return "API error with status code: \(statusCode)"
        case .invalidHttpResponse:
            return "Invalid HTTP response received"
        case .invalidRequest:
            return "Invalid request"
        case .authProviderNeeded:
            return "Authentication provider is required"
        case .authNeeded:
            return "Authentication is required"
        case .codable(let modelName, let error):
            return "Failed to encode/decode \(modelName): \(error.localizedDescription)"
        case .noConnection:
            return "No internet connection available"
        case .malformedRequest:
            return "Malformed request"
        case .timeout:
            return "Request timed out"
        case .cannotFindHost:
            return "Cannot find host or connection failed"
        case .cancelled:
            return "Request was cancelled"
        case .certificate:
            return "SSL/TLS certificate validation failed"
        case .noCachedDataFound:
            return "No cached data found"
        }
    }
}
