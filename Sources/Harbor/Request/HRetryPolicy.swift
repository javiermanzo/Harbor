//
//  HRetryPolicy.swift
//  Harbor
//
//  Retry policy with exponential backoff and jitter for failed requests.
//

import Foundation

/// Describes how a failed request is retried: which failures are retried, how many retries
/// are made and how long to wait between them, using exponential backoff with a random jitter.
///
/// Only transient failures are retried:
/// - HTTP responses whose status code is in `retryableStatusCodes` (by default 408, 425, 429,
///   500, 502, 503 and 504). Other statuses, such as 400, 404 or 422, are returned immediately.
/// - Transient network errors (`URLError` codes such as `.timedOut`, `.networkConnectionLost`,
///   `.secureConnectionFailed`, `.notConnectedToInternet`, `.cannotConnectToHost`,
///   `.cannotFindHost`, `.dnsLookupFailed`, `.internationalRoamingOff`, `.callIsActive` and
///   `.dataNotAllowed`). Cancellation, certificate (SSL pinning, invalid server or client
///   certificate) and malformed-URL errors are never retried.
///
/// Non-idempotent requests (POST, PATCH) are only retried when `retryNonIdempotentRequests` is
/// `true`, since repeating them may duplicate side effects. The exception are network errors
/// raised before the request reached the server (the host could not be resolved or connected
/// to, or there is no network), which are safe to retry for any method.
///
/// When a `429 Too Many Requests` or `503 Service Unavailable` response carries a `Retry-After`
/// header (delta-seconds or HTTP-date), that delay is used instead of the backoff as long as
/// it does not exceed `HRetryPolicy.maxDelay`. A longer `Retry-After` is not clamped: the
/// request is not retried and the `.api` error is returned immediately, so the caller sees the
/// server's hint.
public struct HRetryPolicy: Sendable {
    /// Upper bound for a single backoff delay, in seconds. A `Retry-After` longer than this
    /// stops the retries instead of being clamped.
    public static let maxDelay: TimeInterval = 60

    /// HTTP status codes retried by default: 408, 425, 429, 500, 502, 503 and 504.
    public static let defaultRetryableStatusCodes: Set<Int> = [408, 425, 429, 500, 502, 503, 504]

    /// Maximum number of retries to perform after the initial attempt fails. A value of 0 disables retries.
    public var maxRetries: Int
    /// Delay before the first retry, in seconds. Subsequent retries scale it by `multiplier`.
    public var baseDelay: TimeInterval
    /// Factor applied to the backoff delay after each failed attempt.
    public var multiplier: Double
    /// Random extra delay range added to every backoff, in seconds, to avoid synchronized retries.
    public var jitter: ClosedRange<TimeInterval>
    /// HTTP status codes that trigger a retry. Any other non-success status is returned immediately.
    public var retryableStatusCodes: Set<Int>
    /// Whether non-idempotent requests (POST, PATCH) are retried after a retryable status code or
    /// a network error that may have happened after the request reached the server.
    public var retryNonIdempotentRequests: Bool

    /// Creates a retry policy.
    /// - Parameters:
    ///   - maxRetries: Maximum number of retries after initial failure. Defaults to 0 (no retries).
    ///   - baseDelay: Delay before the first retry in seconds. Defaults to 0.3. Negative values are clamped to 0.
    ///   - multiplier: Backoff growth factor. Defaults to 2.
    ///   - jitter: Random extra delay range in seconds. Defaults to 0...0.1. Inverted ranges are normalized.
    ///   - retryableStatusCodes: HTTP status codes that trigger a retry. Defaults to `defaultRetryableStatusCodes`.
    ///   - retryNonIdempotentRequests: Whether POST and PATCH requests are retried. Defaults to `false`.
    public init(maxRetries: Int = 0,
                baseDelay: TimeInterval = 0.3,
                multiplier: Double = 2.0,
                jitter: ClosedRange<TimeInterval> = 0...0.1,
                retryableStatusCodes: Set<Int> = HRetryPolicy.defaultRetryableStatusCodes,
                retryNonIdempotentRequests: Bool = false) {
        self.maxRetries = max(0, maxRetries)
        self.baseDelay = max(0, baseDelay)
        self.multiplier = multiplier
        // Normalize inverted jitter ranges so TimeInterval.random(in:) cannot trap.
        self.jitter = jitter.lowerBound <= jitter.upperBound
            ? jitter
            : jitter.upperBound...jitter.lowerBound
        self.retryableStatusCodes = retryableStatusCodes
        self.retryNonIdempotentRequests = retryNonIdempotentRequests
    }

    /// Delay to wait before the given retry, where `retry` is 1 for the first retry.
    /// The result grows as `baseDelay * multiplier^(retry - 1)` plus a random jitter,
    /// and is clamped to `HRetryPolicy.maxDelay`.
    /// - Parameter retry: The 1-based index of the retry about to be made.
    public func delay(forRetry retry: Int) -> TimeInterval {
        let exponential = baseDelay * pow(multiplier, Double(max(0, retry - 1)))
        let delay = exponential + TimeInterval.random(in: jitter)
        return min(max(delay, 0), Self.maxDelay)
    }
}

// MARK: - Retry Classification
extension HRetryPolicy {
    /// Network errors raised before the request reached the server. Retrying them cannot
    /// duplicate side effects, so they are retried for any HTTP method.
    private static let preConnectionErrorCodes: Set<URLError.Code> = [
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .notConnectedToInternet,
        .internationalRoamingOff,
        .callIsActive,
        .dataNotAllowed
    ]

    /// Transient network errors that may have happened after the request was sent, including a
    /// generic TLS failure (`.secureConnectionFailed`: a dropped handshake or a reset, as
    /// opposed to a rejected certificate, which is never retried).
    /// They are retried only for idempotent requests unless `retryNonIdempotentRequests` is set.
    private static let inFlightErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .networkConnectionLost,
        .secureConnectionFailed
    ]

    /// Whether the given method may be retried after the request possibly reached the server.
    /// - Parameter method: The HTTP method of the request.
    func allowsRetry(for method: HHttpMethod) -> Bool {
        method.isIdempotent || retryNonIdempotentRequests
    }

    /// Whether a response with the given status code should be retried.
    /// - Parameters:
    ///   - statusCode: The HTTP status code of the response.
    ///   - method: The HTTP method of the request.
    func shouldRetry(statusCode: Int, method: HHttpMethod) -> Bool {
        retryableStatusCodes.contains(statusCode) && allowsRetry(for: method)
    }

    /// Whether a request that failed with the given network error should be retried.
    /// Cancellation, certificate and malformed-URL errors are never retried.
    /// - Parameters:
    ///   - urlError: The network error.
    ///   - method: The HTTP method of the request.
    func shouldRetry(urlError: URLError, method: HHttpMethod) -> Bool {
        if Self.preConnectionErrorCodes.contains(urlError.code) {
            return true
        }
        return Self.inFlightErrorCodes.contains(urlError.code) && allowsRetry(for: method)
    }

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
        switch mockedError {
        case .api(let statusCode, _):
            return shouldRetry(statusCode: statusCode, method: method)
        case .invalidHttpResponse:
            return allowsRetry(for: method)
        case .timeout:
            return shouldRetry(urlError: URLError(.timedOut), method: method)
        case .noConnection:
            return shouldRetry(urlError: URLError(.notConnectedToInternet), method: method)
        case .cannotFindHost:
            return shouldRetry(urlError: URLError(.cannotFindHost), method: method)
        case .cannotConnectToHost:
            return shouldRetry(urlError: URLError(.cannotConnectToHost), method: method)
        case .networkFailure(let urlError):
            return shouldRetry(urlError: urlError, method: method)
        default:
            return false
        }
    }
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
