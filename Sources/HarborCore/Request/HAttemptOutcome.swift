//
//  HAttemptOutcome.swift
//  HarborCore
//
//  Created by Javier Manzo on 16/11/2026.
//

import Foundation

/// Outcome of a single attempt in the retry loop. Carries the final response when the
/// loop should exit; otherwise signals a retry or a 401 that may be retried with refreshed
/// credentials.
package enum HAttemptOutcome<Response: Sendable> {
    /// The request is done; return the response to the caller.
    case finish(Response)
    /// The attempt failed in a retryable way; the loop runs another attempt after the given
    /// delay (from `Retry-After`), or after the policy's backoff when `nil`.
    case retry(after: TimeInterval?)
    /// The server rejected the credentials; the loop decides whether a refreshed header allows another attempt.
    case unauthorized
}
