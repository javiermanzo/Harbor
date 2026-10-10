//
//  HRequestManager+Auth.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - Authorization
extension HRequestManager {
    /// Fetches the provider's authorization header for requests that need auth.
    /// Fails with `.authProviderNeeded` when the request needs auth but no provider is
    /// configured. A provider returning `nil` means no credentials are available and the
    /// request goes out without an authorization header.
    /// - Parameter request: The target request.
    /// - Returns: `Result` containing optional header or error.
    static func authorizationHeaderIfNeeded<P: HRequestBaseRequestProtocol>(for request: P) async -> Result<HAuthorizationHeader?, HRequestError> {
        guard request.needsAuth else { return .success(nil) }

        guard let authProvider = HConfig.shared.authProvider else {
            return .failure(.authProviderNeeded)
        }

        return .success(await authProvider.getAuthorizationHeader())
    }

    /// Resolves the authorization header for cache vary-key computation without failing the
    /// flow: a missing provider must not turn a cache lookup into an error.
    /// - Parameter request: The target request.
    /// - Returns: Optional authorization header.
    static func cacheAuthHeader<P: HRequestBaseRequestProtocol>(for request: P) async -> HAuthorizationHeader? {
        guard case .success(let authHeader) = await authorizationHeaderIfNeeded(for: request) else { return nil }
        return authHeader
    }

    /// Records the credential an authenticated GET request succeeded with, so offline lookups
    /// can find its credential-namespaced cache entry without consulting the provider.
    /// Requests that do not need auth or were sent without credentials record nothing.
    /// - Parameters:
    ///   - authHeader: The authorization header the successful attempt was sent with.
    ///   - request: The request that succeeded.
    static func rememberAuthHeader(_ authHeader: HAuthorizationHeader?, for request: any HGetRequestProtocol) {
        guard request.needsAuth, let authHeader, let key = request.cacheNamespaceKey() else { return }
        if rememberedAuthHeaders.count >= maxRememberedAuthHeaders, rememberedAuthHeaders[key] == nil {
            rememberedAuthHeaders.removeAll()
        }
        rememberedAuthHeaders[key] = authHeader
    }

    /// The credential an authenticated GET request last succeeded with, if remembered.
    /// - Parameter request: The request being looked up.
    static func rememberedAuthHeader(for request: any HGetRequestProtocol) -> HAuthorizationHeader? {
        guard request.needsAuth, let key = request.cacheNamespaceKey() else { return nil }
        return rememberedAuthHeaders[key]
    }

    /// Forgets the credentials remembered for offline lookups. Called when the auth provider
    /// is replaced and when the cache is cleared, so a previous user's credential never keys a
    /// lookup for the next one. Also starts a new `cacheGeneration`, so responses of requests
    /// already in flight are not written back to the cache.
    static func forgetRememberedAuthHeaders() {
        rememberedAuthHeaders.removeAll()
        cacheGeneration &+= 1
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
    ///   notified while resolving it), or `.giveUp(.authNeeded)`.
    static func refreshAuthorization(
        needsAuth: Bool,
        usedHeader: HAuthorizationHeader?,
        authRetriesRemaining: Int,
        providerNotified: Bool
    ) async -> HAuthRefresh {
        guard needsAuth, let authProvider = HConfig.shared.authProvider else {
            return .giveUp(.authNeeded)
        }

        // The retried attempt was rejected too: the request fails with .authNeeded. Make sure
        // the provider learns about it exactly once per request.
        guard authRetriesRemaining > 0 else {
            if !providerNotified {
                await notifyAuthFailed(provider: authProvider, rejectedHeader: usedHeader)
            }
            return .giveUp(.authNeeded)
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
            return .giveUp(.authNeeded)
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
