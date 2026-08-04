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
    /// Cannot find the specified host.
    case cannotFindHost
    /// SSL/TLS certificate validation failed.
    case certificate
    /// Request was cancelled.
    case cancelled
    /// No cached data found for cache-only request.
    case noCachedDataFound
}

extension HJRPCRequestError {
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
        case .malformedRequest:
            return .malformedRequest
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
        }
    }
}
