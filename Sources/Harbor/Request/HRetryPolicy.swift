//
//  HRetryPolicy.swift
//  Harbor
//
//  Retry policy with exponential backoff and jitter for failed requests.
//

import Foundation

/// Describes how a failed request is retried: how many attempts are made and how long
/// to wait between them, using exponential backoff with a random jitter.
public struct HRetryPolicy: Sendable {
    /// Upper bound for a single backoff delay, in seconds.
    public static let maxDelay: TimeInterval = 60

    /// Total number of attempts, including the initial one. A value of 1 disables retries.
    public var maxAttempts: Int
    /// Delay before the first retry, in seconds. Subsequent retries scale it by `multiplier`.
    public var baseDelay: TimeInterval
    /// Factor applied to the backoff delay after each failed attempt.
    public var multiplier: Double
    /// Random extra delay range added to every backoff, in seconds, to avoid synchronized retries.
    public var jitter: ClosedRange<TimeInterval>

    /// Creates a retry policy.
    /// - Parameters:
    ///   - maxAttempts: Total number of attempts including the initial one. Defaults to 1 (no retries).
    ///   - baseDelay: Delay before the first retry in seconds. Defaults to 0.3. Negative values are clamped to 0.
    ///   - multiplier: Backoff growth factor. Defaults to 2.
    ///   - jitter: Random extra delay range in seconds. Defaults to 0...0.1. Inverted ranges are normalized.
    public init(maxAttempts: Int = 1, baseDelay: TimeInterval = 0.3, multiplier: Double = 2, jitter: ClosedRange<TimeInterval> = 0...0.1) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = max(0, baseDelay)
        self.multiplier = multiplier
        // Normalize inverted jitter ranges so TimeInterval.random(in:) cannot trap.
        self.jitter = jitter.lowerBound <= jitter.upperBound
            ? jitter
            : jitter.upperBound...jitter.lowerBound
    }

    /// Delay to wait before the given retry, where `retry` is 1 for the first retry.
    /// The result grows as `baseDelay * multiplier^(retry - 1)` plus a random jitter,
    /// and is clamped to `HRetryPolicy.maxDelay`.
    public func delay(forRetry retry: Int) -> TimeInterval {
        let exponential = baseDelay * pow(multiplier, Double(max(0, retry - 1)))
        let delay = exponential + TimeInterval.random(in: jitter)
        return min(max(delay, 0), Self.maxDelay)
    }
}
