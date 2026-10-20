//
//  HRequestManager+AttemptLoop.swift
//  Harbor
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation

// MARK: - Attempt Loop

extension HRequestManager {
    /// The attempt loop shared by the REST pipeline and the other Harbor products (e.g. the
    /// WebSocket handshake): retries with `Retry-After` or backoff delays, the 401 refresh
    /// flow (`authFailed()` at most once over the loop) and the cancellation check before
    /// every attempt. See `runAttempts` for the REST entry point.
    /// - Parameters:
    ///   - needsAuth: Whether the operation needs auth; a 401 on one that does not gives up
    ///     without consulting the provider.
    ///   - retryPolicy: Optional retry policy configuration.
    ///   - authHeader: The authorization header of the first attempt.
    ///   - failWith: Closure producing the response for an error the loop itself fails with
    ///     (cancellation, an exhausted auth refresh); it also logs it.
    ///   - executeAttempt: Closure performing a single attempt with the header to use and
    ///     whether another attempt remains.
    /// - Returns: The final `Response` after all attempt iterations.
    package static func runAttemptLoop<Response: Sendable>(
        needsAuth: Bool,
        retryPolicy: HRetryPolicy?,
        authHeader: HAuthorizationHeader?,
        failWith: @escaping (HRequestError) async -> Response,
        executeAttempt: @escaping (HAuthorizationHeader?, Bool) async -> HAttemptOutcome<Response>
    ) async -> Response {
        var currentAuthHeader = authHeader
        var retriesPerformed = 0
        var authRetriesRemaining = maxAuthRetries
        var providerNotified = false
        var pendingDelay: TimeInterval?
        let maxRetries = retryPolicy?.maxRetries ?? 0

        while true {
            if let delay = pendingDelay {
                pendingDelay = nil
                _ = await sleep(seconds: delay)
            }

            guard !Task.isCancelled else {
                return await failWith(.cancelled)
            }

            let canRetry = retriesPerformed < maxRetries

            switch await executeAttempt(currentAuthHeader, canRetry) {
            case .finish(let response):
                return response
            case .retry(let retryAfter):
                retriesPerformed += 1
                pendingDelay = retryAfter ?? retryPolicy?.delay(forRetry: retriesPerformed) ?? 0
            case .unauthorized:
                switch await refreshAuthorization(needsAuth: needsAuth, usedHeader: currentAuthHeader, authRetriesRemaining: authRetriesRemaining, providerNotified: providerNotified) {
                case .retry(let freshHeader, let notified):
                    currentAuthHeader = freshHeader
                    authRetriesRemaining -= 1
                    providerNotified = providerNotified || notified
                case .giveUp:
                    return await failWith(.authNeeded)
                }
            }
        }
    }
}
