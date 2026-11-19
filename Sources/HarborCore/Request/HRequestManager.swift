//
//  HRequestManager.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

/// The infrastructure shared by every product's request pipeline: connectivity pre-check,
/// authentication with its `401` refresh flow, the retry loop, error mapping, and the pool
/// of internally built `URLSession`s. REST-only parts (mocks, caching, decoding) extend it in `Harbor`.
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

    /// Number of completed `authFailed()` notifications per rejected authorization header, so
    /// a request that checked for a rotated header while a notification finished does not
    /// start another one. Keyed by a SHA-256 digest (see `authFailureKey(for:)`), so rejected
    /// credentials are not kept in memory; emptied when the provider changes and bounded by
    /// `maxCompletedAuthFailures`.
    static var completedAuthFailures: [String: Int] = [:]

    /// Bound of `completedAuthFailures`; past it the records are dropped. A request racing that
    /// reset may skip its own `authFailed()` call, only for a header the provider was already
    /// notified about.
    static let maxCompletedAuthFailures = 64

    /// Incremented by `Harbor.setAuthProvider(_:)`. The REST layer derives from it when its
    /// remembered credentials and in-flight cache writes stop being valid (see
    /// `HRequestManager+RESTState.swift`), so shared code never has to know about them.
    package static var authGeneration = 0

    /// Called by `Harbor.setAuthProvider(_:)` right after `authGeneration` changes. A single
    /// slot, owned by the REST product (`installAuthProviderObserver`), which remembers
    /// credentials for offline lookups and drops them at once instead of when next read.
    package static var authProviderDidChange: (@HRequestManagerActor () -> Void)?
}
