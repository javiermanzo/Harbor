//
//  HRequestBaseRequestProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - Base Protocol
/// The requirements shared by every REST request. Conform to one of the method protocols
/// instead (`HGetRequestProtocol`, `HPostRequestProtocol`, `HPutRequestProtocol`,
/// `HPatchRequestProtocol`, `HDeleteRequestProtocol`); only `url` (plus `Model` for GET and
/// `bodyParameters` for body requests) has no default.
public protocol HRequestBaseRequestProtocol: Sendable {
    /// The endpoint URL. It may contain `{name}` placeholders replaced by `pathParameters`.
    var url: String { get }
    /// The HTTP method. Provided by the method protocol the request conforms to.
    var httpMethod: HHttpMethod { get }
    /// Whether the request carries the header of the auth provider set with
    /// `Harbor.setAuthProvider(_:)`, and goes through its refresh flow on a `401`. Default: `false`.
    var needsAuth: Bool { get }
    /// Optional retry policy for transient failures (retryable status codes and network
    /// errors, with backoff, jitter and `Retry-After` support). Default: `nil`.
    /// When `nil`, no retries are performed. See `HRetryPolicy` for what is retried.
    var retryPolicy: HRetryPolicy? { get }
    /// Values for the `{name}` placeholders of `url`. They are percent-encoded (`/` included), and
    /// a value containing a `..` segment fails with `.malformedRequest(reason:)`. Default: `nil`.
    var pathParameters: [String: String]? { get }
    /// Additional HTTP headers, applied on top of `Harbor`'s default headers (they win on a
    /// name clash, compared case-insensitively). Default: `nil`.
    var headerParameters: [String: String]? { get }
    /// Idle timeout for this request, in seconds. Default: `nil` (the value set with
    /// `Harbor.setDefaultTimeoutInterval(_:)`, 15 seconds unless changed).
    var timeoutInterval: TimeInterval? { get }
}

// MARK: - Default Implementations

/// Default implementations for `HRequestBaseRequestProtocol`.
public extension HRequestBaseRequestProtocol {
    /// Default: `false`.
    var needsAuth: Bool { false }
    /// Default: `nil`.
    var retryPolicy: HRetryPolicy? { nil }
    /// Default: `nil`.
    var pathParameters: [String: String]? { nil }
    /// Default: `nil`.
    var headerParameters: [String: String]? { nil }
    /// Default: `nil`.
    var timeoutInterval: TimeInterval? { nil }
}
