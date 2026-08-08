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
    /// The request is malformed and cannot be processed. The reason describes what failed.
    case malformedRequest(reason: String? = nil)
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
    /// A network error that does not map to a more specific case. Wraps the original `URLError`.
    case networkFailure(URLError)
}

// MARK: - URLError Mapping
extension HRequestError {
    /// Maximum number of characters of a response body included in error descriptions.
    private static let bodyPreviewLimit = 500

    /// Maps a raw `URLError` to a strongly typed `HRequestError`.
    /// - Parameter error: The error.
    static func mapURLError(_ error: URLError) -> HRequestError {
        switch error.code {
        case .cancelled:
            return .cancelled
        case .badURL:
            return .malformedRequest(reason: "Invalid URL: \(error.localizedDescription)")
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return .cannotFindHost
        case .serverCertificateUntrusted:
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
    public var errorDescription: String? {
        switch self {
        case .api(let statusCode, let data):
            var description = "API error with status code: \(statusCode)"
            guard !data.isEmpty else { return description }
            if let body = String(data: data, encoding: .utf8) {
                description += ", body: \(body.prefix(Self.bodyPreviewLimit))"
            } else {
                description += ", body: \(data.count) bytes of non-UTF-8 data"
            }
            return description
        case .invalidHttpResponse:
            return "Invalid HTTP response received"
        case .invalidRequest:
            return "Invalid request"
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
            return "Cannot find host or connection failed"
        case .cancelled:
            return "Request was cancelled"
        case .certificate:
            return "SSL/TLS certificate validation failed"
        case .noCachedDataFound:
            return "No cached data found"
        case .networkFailure(let error):
            return "Network request failed (\(error.code.rawValue)): \(error.localizedDescription)"
        }
    }
}
