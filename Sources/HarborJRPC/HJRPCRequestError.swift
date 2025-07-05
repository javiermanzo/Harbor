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
    case apiError(statusCode: Int, data: Data)
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
    case codableError(modelName: String, error: Error)
    /// No internet connection available.
    case noConnectionError
    /// The request is malformed and cannot be processed.
    case malformedRequestError
    /// Request timed out.
    case timeoutError
    /// Cannot find the specified host.
    case cannotFindHost
    /// Request was cancelled.
    case cancelled
}

extension HJRPCRequestError {
    static func getError(hRequestError: HRequestError) -> HJRPCRequestError {
        switch hRequestError {
        case .apiError(let statusCode, let data):
            return .apiError(statusCode: statusCode, data: data)
        case .invalidHttpResponse:
            return .invalidHttpResponse
        case .invalidRequest:
            return .invalidRequest
        case .authProviderNeeded:
            return .authProviderNeeded
        case .authNeeded:
            return .authNeeded
        case .codableError(let modelName, let error):
            return .codableError(modelName: modelName, error: error)
        case .noConnectionError:
            return .noConnectionError
        case .malformedRequestError:
            return .malformedRequestError
        case .timeoutError:
            return .timeoutError
        case .cannotFindHost:
            return .cannotFindHost
        case .cancelled:
            return .cancelled
        }
    }
}
