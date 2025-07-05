//
//  HRequestError.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

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
    /// Cannot find the specified host.
    case cannotFindHost
    /// Request was cancelled.
    case cancelled
}
