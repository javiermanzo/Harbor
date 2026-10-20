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
    /// header are coalesced across concurrent requests (see `notifyAuthFailed`).
    /// `getAuthorizationHeader()` is called at most twice: once to detect a rotated header and,
    /// only after `authFailed()`, once more for the refreshed header.
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
        if usedHeader != nil, inFlightAuthFailures[usedHeader] == nil,
           let currentHeader = await authProvider.getAuthorizationHeader(),
           currentHeader != usedHeader {
            return .retry(currentHeader, notifiedProvider: false)
        }

        // Notify the provider of the failure so it can trigger its refresh mechanism, then
        // fetch the header it issues afterwards.
        await notifyAuthFailed(provider: authProvider, rejectedHeader: usedHeader)

        guard let freshHeader = await authProvider.getAuthorizationHeader(),
              freshHeader != usedHeader else {
            return .giveUp
        }

        return .retry(freshHeader, notifiedProvider: true)
    }

    /// Calls `authFailed()` on the provider, coalescing concurrent calls: requests rejected
    /// with the same authorization header while a notification for it is in flight await
    /// that notification instead of starting another refresh.
    /// - Parameters:
    ///   - provider: The configured auth provider.
    ///   - rejectedHeader: The authorization header the server rejected.
    static func notifyAuthFailed(provider: any HAuthProviderProtocol, rejectedHeader: HAuthorizationHeader?) async {
        if let inFlight = inFlightAuthFailures[rejectedHeader] {
            await inFlight.value
            return
        }

        let notification = Task {
            await provider.authFailed()
        }
        inFlightAuthFailures[rejectedHeader] = notification
        await notification.value
        if inFlightAuthFailures[rejectedHeader] == notification {
            inFlightAuthFailures[rejectedHeader] = nil
        }
    }
}
