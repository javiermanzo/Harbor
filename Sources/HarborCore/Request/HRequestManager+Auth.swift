//
//  HRequestManager+Auth.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - Authorization

extension HRequestManager {
    /// Fetches the provider's authorization header when `needsAuth` is set. Used by the REST
    /// pipeline and the other products (e.g. the WebSocket handshake).
    /// - Parameter needsAuth: Whether the operation needs auth.
    /// - Returns: `.success(nil)` when no auth is needed or the provider has no credentials,
    ///   `.failure(.authProviderNeeded)` when auth is needed but no provider is configured.
    package static func authorizationHeader(needsAuth: Bool) async -> Result<HAuthorizationHeader?, HRequestError> {
        guard needsAuth else { return .success(nil) }

        guard let authProvider = HConfig.shared.authProvider else {
            return .failure(.authProviderNeeded)
        }

        return .success(await authProvider.getAuthorizationHeader())
    }

    /// Handles a 401 for a request that needs auth. While an auth retry remains, the provider's
    /// current header is compared with the rejected one: a header already rotated (a refresh
    /// triggered by another request completed after this attempt was sent) is retried with
    /// right away, without `authFailed()`; otherwise the provider is notified through
    /// `authFailed()` and asked for its header again, and a retry is offered only when the
    /// header changed. A provider without credentials (a `nil` header) cannot satisfy a 401,
    /// so the flow gives up with `.authNeeded`.
    ///
    /// `authFailed()` is called at most once per request, and always once when a request that
    /// needs auth finally fails with `.authNeeded` after a 401: when the auth retries are
    /// exhausted (the retried attempt was rejected too) and the provider was not notified yet,
    /// it is notified before giving up, so a provider that rotates its header on every call
    /// still learns that its credentials are rejected. Notifications for the same rejected
    /// header are coalesced across concurrent requests (see `notifyAuthFailed`), including a
    /// notification that completed while this request was checking for a rotated header.
    /// While handling the 401, `getAuthorizationHeader()` is called at most twice: once to
    /// detect a rotated header and, only after `authFailed()`, once more for the refreshed one.
    ///
    /// The flow gives up when the auth provider is replaced (`Harbor.setAuthProvider(_:)`)
    /// while it waits, so a request never retries with a header from a provider that was
    /// removed, and when the calling task is cancelled (it does not wait for `authFailed()`).
    /// - Parameters:
    ///   - needsAuth: Whether the request needs auth. A request that opted out has no
    ///     credential to refresh and gives up without consulting the provider.
    ///   - usedHeader: The authorization header the rejected attempt was sent with.
    ///   - authRetriesRemaining: Auth retries still available for this request.
    ///   - providerNotified: Whether `authFailed()` was already called for this request.
    /// - Returns: `.retry` with the header for the next attempt (and whether the provider was
    ///   notified while resolving it), or `.giveUp`.
    package static func refreshAuthorization(
        needsAuth: Bool,
        usedHeader: HAuthorizationHeader?,
        authRetriesRemaining: Int,
        providerNotified: Bool
    ) async -> HAuthRefresh {
        guard needsAuth, let authProvider = HConfig.shared.authProvider else {
            return .giveUp
        }
        // Checked after every suspension: a provider replaced meanwhile must not be used.
        let generation = authGeneration
        var isCurrent: Bool { generation == authGeneration && !Task.isCancelled }

        // The retried attempt was rejected too: the request fails with .authNeeded. Make sure
        // the provider learns about it exactly once per request.
        guard authRetriesRemaining > 0 else {
            if !providerNotified {
                await notifyAuthFailed(provider: authProvider, rejectedHeader: usedHeader)
            }
            return .giveUp
        }

        // A late 401 for a header the provider has already rotated: retry with the current
        // header instead of asking for another refresh.
        let completedNotifications = completedAuthFailures[usedHeader, default: 0]
        if usedHeader != nil, inFlightAuthFailures[usedHeader] == nil {
            let currentHeader = await authProvider.getAuthorizationHeader()
            guard isCurrent else { return .giveUp }
            if let currentHeader, currentHeader != usedHeader {
                return .retry(currentHeader, notifiedProvider: false)
            }
        }

        // Notify the provider of the failure so it can trigger its refresh mechanism, unless a
        // notification for this header completed while the rotated header was checked, then
        // fetch the header it issues afterwards.
        if completedAuthFailures[usedHeader, default: 0] == completedNotifications {
            await notifyAuthFailed(provider: authProvider, rejectedHeader: usedHeader)
            guard isCurrent else { return .giveUp }
        }

        guard let freshHeader = await authProvider.getAuthorizationHeader(),
              isCurrent,
              freshHeader != usedHeader else {
            return .giveUp
        }

        return .retry(freshHeader, notifiedProvider: true)
    }

    /// Calls `authFailed()` on the provider, coalescing concurrent calls: requests rejected
    /// with the same authorization header while a notification for it is in flight await
    /// that notification instead of starting another refresh. The notification runs on its
    /// own and cleans up after itself, so a waiter whose task is cancelled stops waiting
    /// right away without cancelling the refresh the other requests share.
    /// - Parameters:
    ///   - provider: The configured auth provider.
    ///   - rejectedHeader: The authorization header the server rejected.
    static func notifyAuthFailed(provider: any HAuthProviderProtocol, rejectedHeader: HAuthorizationHeader?) async {
        if let inFlight = inFlightAuthFailures[rejectedHeader] {
            await waitUnlessCancelled(for: inFlight)
            return
        }

        let notification = Task {
            await provider.authFailed()
        }
        inFlightAuthFailures[rejectedHeader] = notification
        Task {
            await notification.value
            completedAuthFailures[rejectedHeader, default: 0] &+= 1
            if inFlightAuthFailures[rejectedHeader] == notification {
                inFlightAuthFailures[rejectedHeader] = nil
            }
        }
        await waitUnlessCancelled(for: notification)
    }

    /// Waits for `task` to finish, or returns as soon as the calling task is cancelled.
    /// - Parameter task: The task to wait for. It is not cancelled.
    private static func waitUnlessCancelled(for task: Task<Void, Never>) async {
        let waiter = HLockedState(AuthWaiter())
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let alreadyCancelled = waiter.withLock { state -> Bool in
                    guard !state.isCancelled else { return true }
                    state.continuation = continuation
                    return false
                }
                if alreadyCancelled {
                    continuation.resume()
                    return
                }
                Task {
                    await task.value
                    waiter.withLock { $0.resume() }
                }
            }
        } onCancel: {
            waiter.withLock { state in
                state.isCancelled = true
                state.resume()
            }
        }
    }
}

// MARK: - Auth Waiter

/// The continuation of a request waiting for a shared `authFailed()` notification, resumed
/// once by whichever comes first: the notification finishing or the request's cancellation.
private struct AuthWaiter: Sendable {
    /// The suspended waiter, until it is resumed.
    var continuation: CheckedContinuation<Void, Never>?
    /// Whether the waiting task was cancelled.
    var isCancelled = false

    /// Resumes the waiter if it is still suspended.
    mutating func resume() {
        continuation?.resume()
        continuation = nil
    }
}
