//
//  HStatusRetry.swift
//  HarborCore
//
//  Created by Javier Manzo on 16/11/2026.
//

import Foundation

/// Whether a retryable status code may be retried once its `Retry-After` header is considered.
package enum HStatusRetry {
    /// Retry after the server-provided delay, or after the policy's backoff when `nil`.
    case retry(after: TimeInterval?)
    /// The server asked to wait longer than `HRetryPolicy.maxDelay`; the response is returned as-is.
    case giveUp
}

// MARK: - Equatable

extension HStatusRetry: Equatable {}
