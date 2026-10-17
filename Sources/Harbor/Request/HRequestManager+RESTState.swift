//
//  HRequestManager+RESTState.swift
//  Harbor
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation
import HarborCore

// MARK: - REST Cache State

extension HRequestManager {
    /// The authorization header each authenticated GET request last succeeded with, keyed by
    /// its plain cache key (the composite URL). Offline lookups use it to find the
    /// credential-namespaced cache entry without consulting the auth provider, whose header
    /// resolution may refresh a token over the network. Cleared by `forgetRememberedAuthHeaders()`
    /// (`Harbor.clearAllCache()`) and when `Harbor.setAuthProvider(_:)` is called.
    static var rememberedAuthHeaders: [String: HAuthorizationHeader] = [:]

    /// Bound of `rememberedAuthHeaders`; past it the map is reset before recording a new entry.
    static let maxRememberedAuthHeaders = 512

    /// The `authGeneration` the remembered credentials were recorded under.
    private static var rememberedAuthGeneration = 0

    /// Incremented when the cache is cleared; part of `cacheGeneration`.
    private static var clearedCacheGeneration = 0

    /// Changes whenever cached content must not be written back by requests already in
    /// flight: when the cache is cleared or the auth provider is replaced (e.g. on logout). A
    /// response whose attempt started under an earlier generation is returned to its caller
    /// but neither stored nor remembered, so it cannot resurrect a previous user's data.
    static var cacheGeneration: Int {
        clearedCacheGeneration &+ authGeneration
    }

    /// Forgets the credentials remembered for offline lookups. Called when the cache is
    /// cleared, so a previous user's credential never keys a lookup for the next one. Also
    /// starts a new `cacheGeneration`, so responses of requests already in flight are not
    /// written back to the cache. Replacing the auth provider has the same effect without a
    /// call: it changes `authGeneration`, which `rememberedAuthHeaders` follows.
    static func forgetRememberedAuthHeaders() {
        rememberedAuthHeaders.removeAll()
        clearedCacheGeneration &+= 1
    }

    /// Makes `Harbor.setAuthProvider(_:)` drop the remembered credentials at once. Installed
    /// when the first credential is recorded: until then there is nothing to forget.
    private static func installAuthProviderObserver() {
        guard authProviderDidChange == nil else { return }
        authProviderDidChange = { discardRememberedAuthHeadersIfProviderChanged() }
    }

    /// Drops the remembered credentials when the auth provider was replaced since they were
    /// recorded.
    private static func discardRememberedAuthHeadersIfProviderChanged() {
        guard rememberedAuthGeneration != authGeneration else { return }
        rememberedAuthHeaders.removeAll()
        rememberedAuthGeneration = authGeneration
    }
}

// MARK: - REST Authorization

extension HRequestManager {
    /// Fetches the provider's authorization header for requests that need auth.
    /// Fails with `.authProviderNeeded` when the request needs auth but no provider is
    /// configured. A provider returning `nil` means no credentials are available and the
    /// request goes out without an authorization header.
    /// - Parameter request: The target request.
    /// - Returns: `Result` containing optional header or error.
    static func authorizationHeaderIfNeeded<P: HRequestBaseRequestProtocol>(for request: P) async -> Result<HAuthorizationHeader?, HRequestError> {
        await authorizationHeader(needsAuth: request.needsAuth)
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
        discardRememberedAuthHeadersIfProviderChanged()
        installAuthProviderObserver()
        if rememberedAuthHeaders.count >= maxRememberedAuthHeaders, rememberedAuthHeaders[key] == nil {
            rememberedAuthHeaders.removeAll()
        }
        rememberedAuthHeaders[key] = authHeader
    }

    /// The credential an authenticated GET request last succeeded with, if remembered.
    /// - Parameter request: The request being looked up.
    static func rememberedAuthHeader(for request: any HGetRequestProtocol) -> HAuthorizationHeader? {
        guard request.needsAuth, let key = request.cacheNamespaceKey() else { return nil }
        discardRememberedAuthHeadersIfProviderChanged()
        return rememberedAuthHeaders[key]
    }
}
