//
//  HRequestManager.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

/// Global actor to manage shared mutable state in a thread-safe way.
/// This actor ensures that Harbor's internal state is accessed safely across concurrent contexts.
@globalActor public actor HRequestManagerActor {
    /// The shared instance of the actor.
    public static let shared = HRequestManagerActor()
}

// MARK: - Isolated Reads

extension HRequestManagerActor {
    /// Runs `body` on `HRequestManagerActor` and returns its result, the equivalent of
    /// `MainActor.run`. Code outside the actor (e.g. another module's non-isolated helpers) uses
    /// it to read Harbor's configuration, whose types are isolated to the actor.
    /// - Parameter body: The closure to run on the actor.
    /// - Returns: The closure's result.
    package static func run<Result: Sendable>(_ body: @HRequestManagerActor @Sendable () -> Result) async -> Result {
        await body()
    }
}

/// Runs Harbor's REST request pipeline: mocks, connectivity pre-check, authentication,
/// retries, caching, decoding and logging. Also owns the internally built `URLSession`s.
@HRequestManagerActor
package enum HRequestManager {
    /// Connectivity monitor used as a pre-check before executing requests.
    /// Owned here (typed as the protocol) so tests can substitute a fake.
    package static var connectivityMonitor: any HRequestManagerMonitorProtocol = HRequestManagerMonitor()

    /// Maximum number of times a request is re-issued with a refreshed authorization header
    /// after a 401. These attempts are ADDITIONAL to the retry policy's `maxRetries` — they
    /// are not deducted from it. Worst-case total attempts per request are
    /// `1 + retryPolicy.maxRetries + maxAuthRetries`.
    static let maxAuthRetries = 1

    /// In-flight `authFailed()` notifications, keyed by the rejected authorization header.
    /// Concurrent requests rejected with the same credential await the same notification
    /// instead of triggering one refresh each.
    static var inFlightAuthFailures: [HAuthorizationHeader?: Task<Void, Never>] = [:]

    /// Incremented by `Harbor.setAuthProvider(_:)`. The REST layer derives from it when its
    /// remembered credentials and in-flight cache writes stop being valid (see
    /// `HRequestManager+RESTState.swift`), so shared code never has to know about them.
    package static var authGeneration = 0

    /// Called by `Harbor.setAuthProvider(_:)` right after `authGeneration` changes. A product
    /// that remembers credentials installs it so they are dropped at once, not when next read.
    package static var authProviderDidChange: (@HRequestManagerActor () -> Void)?
}

// MARK: - Retry Loop Outcomes

/// Outcome of a single attempt in the retry loop. Carries the final response when the
/// loop should exit; otherwise signals a retry, a 401 that may be retried with refreshed
/// credentials, or (inside the attempt only) a `304` without a cached body that is
/// re-fetched unconditionally (`.refetchUnconditionally`).
package enum HAttemptOutcome<Response: Sendable> {
    /// The request is done; return the response to the caller.
    case finish(Response)
    /// The attempt failed in a retryable way; the loop runs another attempt after the given
    /// delay (from `Retry-After`), or after the policy's backoff when `nil`.
    case retry(after: TimeInterval?)
    /// The server rejected the credentials; the loop decides whether a refreshed header allows another attempt.
    case unauthorized
    /// A conditional request got `304` but no cached body exists; the attempt re-issues the
    /// request without validators. Consumed inside the attempt, never by the retry loop.
    case refetchUnconditionally
}

/// Outcome of evaluating a 401 response against the auth provider. The retry case carries
/// the refreshed authorization header, which the loop applies to the next attempt's
/// `URLRequest` without touching the request object.
package enum HAuthRefresh {
    /// The provider issued a different authorization header; retry with it applied.
    /// `notifiedProvider` tells whether `authFailed()` was called to obtain it.
    case retry(HAuthorizationHeader, notifiedProvider: Bool)
    /// No further attempt is possible; finish with the given error.
    case giveUp(HRequestError)
}
