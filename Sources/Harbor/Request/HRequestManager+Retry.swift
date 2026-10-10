//
//  HRequestManager+Retry.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - Errors, Retry-After and Backoff
extension HRequestManager {
    /// Maps a `URLError` thrown while performing a request. A TLS challenge rejected by
    /// Harbor's session delegate (SSL pinning mismatch, untrusted chain) surfaces from
    /// `URLSession` as `URLError.cancelled`; the task context records it, so it is reported
    /// as `.certificate` instead of `.cancelled`. Otherwise a cancelled task maps to
    /// `.cancelled` and the rest goes through `HRequestError.mapURLError(_:)`.
    /// - Parameters:
    ///   - error: The thrown error.
    ///   - trustEvaluationFailed: Whether Harbor's delegate rejected a TLS challenge for the task.
    /// - Returns: The mapped `HRequestError`.
    static func mapTransportError(_ error: URLError, trustEvaluationFailed: Bool) -> HRequestError {
        if trustEvaluationFailed {
            return .certificate
        }
        if error.code == .cancelled || Task.isCancelled {
            return .cancelled
        }
        return HRequestError.mapURLError(error)
    }

    /// Maps an error that is not a `URLError` thrown while performing a request. Such errors
    /// are never retried; the original error is preserved in `.unknown` unless the task was
    /// cancelled.
    /// - Parameter error: The thrown error.
    /// - Returns: The mapped `HRequestError`.
    static func mapNonURLError(_ error: Error) -> HRequestError {
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        return .unknown(error)
    }

    /// Delay requested by a `Retry-After` header on a `429` or `503` response, in seconds.
    /// Both forms are supported: delta-seconds and HTTP-date. The value is returned as the
    /// server sent it, not capped (see `statusRetry(statusCode:httpResponse:now:)`); `nil`
    /// means the header is absent, invalid or not applicable.
    /// - Parameters:
    ///   - statusCode: The HTTP status code of the response.
    ///   - httpResponse: The response carrying the header.
    ///   - now: The reference date for HTTP-date values.
    static func retryAfterDelay(statusCode: Int, httpResponse: HTTPURLResponse?, now: Date = Date()) -> TimeInterval? {
        guard statusCode == 429 || statusCode == 503,
              let rawValue = httpResponse?.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        let value = rawValue.trimmingCharacters(in: .whitespaces)
        if let deltaSeconds = Int(value) {
            guard deltaSeconds >= 0 else { return nil }
            return TimeInterval(deltaSeconds)
        }
        if let date = HCache.Manager.parseHTTPDate(value) {
            return max(0, date.timeIntervalSince(now))
        }
        return nil
    }

    /// Decides whether a retryable status code is retried, honoring its `Retry-After` header.
    /// A delay up to `HRetryPolicy.maxDelay` is waited for instead of the policy's backoff. A
    /// longer one is not clamped: the request is not retried and the `.api` error is returned
    /// right away, so the caller sees the server's hint instead of a retry that is too early.
    /// - Parameters:
    ///   - statusCode: The HTTP status code of the response.
    ///   - httpResponse: The response carrying the header.
    ///   - now: The reference date for HTTP-date values.
    static func statusRetry(statusCode: Int, httpResponse: HTTPURLResponse?, now: Date = Date()) -> HStatusRetry {
        let retryAfter = retryAfterDelay(statusCode: statusCode, httpResponse: httpResponse, now: now)
        if let retryAfter, retryAfter > HRetryPolicy.maxDelay {
            return .giveUp
        }
        return .retry(after: retryAfter)
    }

    /// Sleeps for the given number of seconds. Negative values are treated as zero and the
    /// delay is clamped to `HRetryPolicy.maxDelay` before converting to nanoseconds.
    /// - Parameter seconds: The duration to sleep, in seconds.
    /// - Returns: `false` when the task was cancelled before or during the sleep.
    @discardableResult
    static func sleep(seconds: TimeInterval) async -> Bool {
        let clampedSeconds = min(max(seconds, 0), HRetryPolicy.maxDelay)
        guard clampedSeconds > 0 else { return !Task.isCancelled }
        do {
            if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
                try await Task.sleep(for: .seconds(clampedSeconds))
            } else {
                try await Task.sleep(nanoseconds: UInt64(clampedSeconds * 1_000_000_000))
            }
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

/// Whether a retryable status code may be retried once its `Retry-After` header is considered.
enum HStatusRetry {
    /// Retry after the server-provided delay, or after the policy's backoff when `nil`.
    case retry(after: TimeInterval?)
    /// The server asked to wait longer than `HRetryPolicy.maxDelay`; the response is returned as-is.
    case giveUp
}

// MARK: - Equatable

extension HStatusRetry: Equatable {}
