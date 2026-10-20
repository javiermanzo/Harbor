//
//  HHttpMethod.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import HarborCore

/// HTTP methods supported by Harbor networking library.
public enum HHttpMethod: String, Sendable {
    /// GET method for retrieving data.
    case get = "GET"
    /// POST method for creating new resources.
    case post = "POST"
    /// PUT method for updating existing resources.
    case put = "PUT"
    /// DELETE method for removing resources.
    case delete = "DELETE"
    /// PATCH method for partially updating resources.
    case patch = "PATCH"
}

// MARK: - Idempotency
extension HHttpMethod {
    /// Whether repeating the request has the same effect as sending it once (RFC 9110 §9.2.2).
    var isIdempotent: Bool {
        switch self {
        case .get, .put, .delete:
            return true
        case .post, .patch:
            return false
        }
    }
}

// MARK: - Retry decisions by method
extension HRetryPolicy {
    /// Whether a mocked attempt that failed with the given error should be retried. The error
    /// is classified like the real failure it stands for: `.api` by its status code,
    /// `.invalidHttpResponse` like a non-HTTP response, and the transport errors by their
    /// network error (`.timeout` as `.timedOut`, `.noConnection` as `.notConnectedToInternet`,
    /// `.cannotFindHost`, `.cannotConnectToHost` and the `URLError` wrapped by
    /// `.networkFailure`). Any other error is never retried.
    /// - Parameters:
    ///   - mockedError: The error configured on the mock.
    ///   - method: The HTTP method of the request.
    func shouldRetry(mockedError: HRequestError, method: HHttpMethod) -> Bool {
        let isIdempotent = method.isIdempotent
        switch mockedError {
        case .api(let statusCode, _):
            return shouldRetry(statusCode: statusCode, isIdempotent: isIdempotent)
        case .invalidHttpResponse:
            return allowsRetry(isIdempotent: isIdempotent)
        case .timeout:
            return shouldRetry(urlError: URLError(.timedOut), isIdempotent: isIdempotent)
        case .noConnection:
            return shouldRetry(urlError: URLError(.notConnectedToInternet), isIdempotent: isIdempotent)
        case .cannotFindHost:
            return shouldRetry(urlError: URLError(.cannotFindHost), isIdempotent: isIdempotent)
        case .cannotConnectToHost:
            return shouldRetry(urlError: URLError(.cannotConnectToHost), isIdempotent: isIdempotent)
        case .networkFailure(let urlError):
            return shouldRetry(urlError: urlError, isIdempotent: isIdempotent)
        default:
            return false
        }
    }
}
