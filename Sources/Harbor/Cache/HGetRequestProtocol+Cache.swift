//
//  HGetRequestProtocol+Cache.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import Foundation

public extension HGetRequestProtocol {

    /// Returns the cached response of this request, decoded with `parseData(data:model:)`,
    /// without touching the network.
    ///
    /// - `.custom`: only an entry that is still fresh (or within its `stale-while-revalidate`
    ///   window) is returned.
    /// - `.urlCache`: the stored 2xx response is returned unless its headers mark it as
    ///   explicitly stale (`no-cache` / `no-store`, an elapsed `max-age` or
    ///   `Expires`, or an elapsed `Last-Modified` heuristic); a response without freshness
    ///   headers is served. The check is skipped when the cache policy prefers cached data
    ///   (`.returnCacheDataElseLoad`, `.returnCacheDataDontLoad`).
    /// - `.disabled`: always `nil`.
    ///
    /// For requests that need auth, the entry stored for the credential currently issued by
    /// the auth provider is returned; an entry stored for another credential never is.
    /// - Returns: The cached model, or `nil` when there is no usable entry or it cannot be decoded.
    func cache() async -> Model? {
        await cachedModel(authHeader: nil)
    }

    /// Returns the `ETag` stored with the cached response of this request, if any, so you can
    /// send your own conditional request. Works with the `.custom` and `.urlCache` cache types. For requests that need auth, the
    /// credential is resolved from the configured auth provider.
    func cachedETag() async -> String? {
        switch await effectiveCacheType() {
        case .custom:
            guard let lookup = await cacheLookup(authHeader: nil) else { return nil }
            return await HCache.Manager.shared.getETag(forKey: lookup.key)

        case .urlCache(let urlCache, _):
            guard let urlRequest = await urlRequest(),
                  let cached = urlCache.cachedResponse(for: urlRequest),
                  let httpResponse = cached.response as? HTTPURLResponse else { return nil }
            return httpResponse.value(forHTTPHeaderField: "ETag")

        case .disabled:
            return nil
        }
    }

    /// Removes the cached response of this request. Works with the `.custom` and `.urlCache`
    /// cache types; use `Harbor.clearAllCache()` to remove everything. For requests that need auth, the
    /// entry of the credential currently issued by the auth provider is removed, together
    /// with any entry stored without credentials.
    func clearCache() async {
        switch await effectiveCacheType() {
        case .urlCache(let urlCache, _):
            // Remove from URLCache
            guard let urlRequest = await urlRequest() else { return }
            urlCache.removeCachedResponse(for: urlRequest)

        case .custom:
            // Remove from custom cache
            guard let url = compositeURL() else { return }
            await HCache.Manager.shared.removeCachedData(for: HCache.Manager.cacheKey(for: url, authHeader: nil))
            if needsAuth, let lookup = await cacheLookup(authHeader: nil) {
                await HCache.Manager.shared.removeCachedData(for: lookup.key)
            }

        case .disabled:
            break
        }
    }
}

extension HGetRequestProtocol {
    /// Implementation of `cache()` for a known authorization header.
    ///
    /// For `.custom`, only entries that are still fresh (or within their
    /// `stale-while-revalidate` window) are returned. For `.urlCache`, the stored 2xx response
    /// is returned unless its headers mark it as explicitly stale (see
    /// `HCache.Manager.isFresh(urlCacheResponse:now:)`): `Cache-Control: no-cache` /
    /// `no-store`, an elapsed explicit lifetime (`max-age`, `Expires`) or an
    /// elapsed `Last-Modified` heuristic. A response without freshness information is served
    /// as stored. The check is skipped when the cache policy explicitly prefers cached data
    /// (`.returnCacheDataElseLoad`, `.returnCacheDataDontLoad`).
    ///
    /// For requests that need auth, entries are namespaced by the credential they were
    /// stored with: an entry stored for one credential is never returned for another.
    /// - Parameter authHeader: The authorization header sent with the request, so
    ///   credential-keyed entries are looked up under the credential they were stored with.
    ///   When nil and the request needs auth, the header is resolved from the configured
    ///   auth provider.
    /// - Returns: The cached model if found and valid, `nil` otherwise.
    func cachedModel(authHeader: HAuthorizationHeader?) async -> Model? {
        let effectiveCacheType = await effectiveCacheType()

        switch effectiveCacheType {
        case .custom(let config):
            guard let lookup = await cacheLookup(authHeader: authHeader) else { return nil }
            return await HCache.Manager.shared.getCachedData(forKey: lookup.key, config: config, requestHeaders: lookup.requestHeaders, decode: cacheDecoder())

        case .urlCache(let urlCache, let requestPolicy):
            guard let urlRequest = await urlRequest(),
                  let cached = urlCache.cachedResponse(for: urlRequest),
                  let httpResponse = cached.response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode) else { return nil }

            let prefersCachedData = requestPolicy == .returnCacheDataElseLoad || requestPolicy == .returnCacheDataDontLoad
            if !prefersCachedData {
                guard await HCache.Manager.isFresh(urlCacheResponse: httpResponse) else { return nil }
            }
            return decodeURLCacheBody(cached.data, in: urlCache, for: urlRequest)

        case .disabled:
            return nil
        }
    }

    /// Saves response data to cache for this request.
    /// Only works with custom cache type. For URLCache, the system handles caching automatically.
    /// - Parameters:
    ///   - data: The response data to cache.
    ///   - response: The HTTP response containing cache headers (optional).
    ///   - authHeader: The authorization header the request was sent with, so the entry is
    ///     stored under that credential. It is never resolved again from the provider: a
    ///     request that needs auth but was sent without a header is not cached.
    func saveCache(_ data: Data, response: HTTPURLResponse?, authHeader: HAuthorizationHeader?) async {
        if case .custom(let config) = await effectiveCacheType(),
           let lookup = await cacheLookup(authHeader: authHeader, resolvingAuthHeader: false) {
            await HCache.Manager.shared.storeData(data, forKey: lookup.key, config: config, response: response, requestHeaders: lookup.requestHeaders)
        }
    }

    /// Returns the cached body to satisfy a `304 Not Modified` response and refreshes the
    /// stored entry (timestamp, expiration and validators) from the revalidation headers.
    /// When `parseData(data:model:)` cannot decode the cached body, `nil` is returned (the
    /// entry is kept, as another request type may share the URL), so the caller can fetch the
    /// full representation.
    /// - Parameters:
    ///   - response: The 304 response whose headers refresh the stored entry (new validators,
    ///     `Cache-Control`, `Expires`). Headers it omits keep the stored values.
    ///   - authHeader: The authorization header the request was sent with (never resolved again).
    /// - Returns: The cached model, or `nil` when no revalidatable entry exists or it cannot be decoded.
    func revalidatedCache(response: HTTPURLResponse?, authHeader: HAuthorizationHeader?) async -> Model? {
        switch await effectiveCacheType() {
        case .custom(let config):
            guard let lookup = await cacheLookup(authHeader: authHeader, resolvingAuthHeader: false),
                  let model = await HCache.Manager.shared.getRevalidatableCachedData(forKey: lookup.key, requestHeaders: lookup.requestHeaders, decode: cacheDecoder()) else { return nil }
            await HCache.Manager.shared.refreshEntry(forKey: lookup.key, response: response, config: config)
            return model

        case .urlCache(let urlCache, _):
            guard let urlRequest = await urlRequest(),
                  let cached = urlCache.cachedResponse(for: urlRequest) else { return nil }
            return decodeURLCacheBody(cached.data, in: urlCache, for: urlRequest)

        case .disabled:
            return nil
        }
    }

    /// Returns an expired cached body while its `stale-if-error` window still allows serving it.
    /// Only works with custom cache type.
    /// - Parameter authHeader: The authorization header the request was sent with (never resolved again).
    func staleCacheOnError(authHeader: HAuthorizationHeader?) async -> Model? {
        guard case .custom = await effectiveCacheType(),
              let lookup = await cacheLookup(authHeader: authHeader, resolvingAuthHeader: false) else { return nil }
        return await HCache.Manager.shared.getStaleOnErrorData(forKey: lookup.key, requestHeaders: lookup.requestHeaders, decode: cacheDecoder())
    }
}

extension HGetRequestProtocol {
    /// Returns a cached body that can stand in for the network while offline:
    /// - `.custom`: a still-fresh entry or, failing that, an expired one whose
    ///   `stale-if-error` window still allows serving it. The stale lookup runs first because
    ///   the fresh lookup evicts expired entries without validators, which would delete a
    ///   stale-servable entry before it could be returned; the two lookups never overlap.
    /// - `.urlCache`: the stored 2xx response, unless the request's cache policy ignores
    ///   local data (`.reloadIgnoringLocalCacheData`, `.reloadIgnoringLocalAndRemoteCacheData`).
    /// - `.disabled`: nothing.
    /// - Parameters:
    ///   - authHeader: The authorization header sent with the request (see `cachedModel(authHeader:)`).
    ///   - resolvingAuthHeader: Whether a missing header is resolved from the auth provider.
    func offlineCache(authHeader: HAuthorizationHeader?, resolvingAuthHeader: Bool) async -> Model? {
        switch await effectiveCacheType() {
        case .custom(let config):
            guard let lookup = await cacheLookup(authHeader: authHeader, resolvingAuthHeader: resolvingAuthHeader) else { return nil }
            if let stale = await HCache.Manager.shared.getStaleOnErrorData(forKey: lookup.key, requestHeaders: lookup.requestHeaders, decode: cacheDecoder()) {
                return stale
            }
            return await HCache.Manager.shared.getCachedData(forKey: lookup.key, config: config, requestHeaders: lookup.requestHeaders, decode: cacheDecoder())

        case .urlCache(let urlCache, let requestPolicy):
            guard requestPolicy != .reloadIgnoringLocalCacheData,
                  requestPolicy != .reloadIgnoringLocalAndRemoteCacheData,
                  let urlRequest = await urlRequest(),
                  let cached = urlCache.cachedResponse(for: urlRequest),
                  let httpResponse = cached.response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode) else { return nil }
            return decodeURLCacheBody(cached.data, in: urlCache, for: urlRequest)

        case .disabled:
            return nil
        }
    }

    /// The plain (credential-less) cache key of this request: its composite URL. Used by
    /// `HRequestManager` to remember the credential an authenticated request succeeded with.
    /// - Returns: The key, or nil if the URL cannot be built.
    func cacheNamespaceKey() -> String? {
        compositeURL().map { HCache.Manager.cacheKey(for: $0, authHeader: nil) }
    }
}

private extension HGetRequestProtocol {

    /// Resolves the effective cache type for this request.
    /// Uses the request-specific cache type if set, otherwise falls back to the global default.
    /// - Returns: The effective `HCache.CacheType` to use for this request.
    func effectiveCacheType() async -> HCache.CacheType {
        if let requestCacheType = self.cacheType {
           return requestCacheType
        } else {
            return await HConfig.shared.cacheType
        }
    }

    /// Builds a URLRequest for this request.
    /// - Returns: The configured URLRequest, or nil if the request cannot be built.
    func urlRequest() async -> URLRequest? {
        try? await HURLBuilder.buildUrlRequest(request: self)
    }

    /// Decodes cached bodies exactly like the network flow: through `parseData(data:model:)`.
    func cacheDecoder() -> @Sendable (Data) throws -> Model {
        return { data in try self.parseData(data: data, model: Model.self) }
    }

    /// Decodes a `URLCache` body with `parseData(data:model:)`, removing the stored response
    /// when it cannot be decoded anymore.
    func decodeURLCacheBody(_ data: Data, in urlCache: URLCache, for urlRequest: URLRequest) -> Model? {
        do {
            return try parseData(data: data, model: Model.self)
        } catch {
            urlCache.removeCachedResponse(for: urlRequest)
            return nil
        }
    }

    /// Resolves the custom-cache key and the headers that will effectively be sent with this
    /// request: the global default headers merged with the request-specific ones and the
    /// authorization header. The headers evaluate `Vary` consistently with what is actually
    /// sent on the wire.
    ///
    /// When `authHeader` is nil and the request needs auth, the header is resolved from the
    /// configured auth provider (once) so the key matches the one the network flow uses. Pass
    /// `resolvingAuthHeader: false` to skip the provider entirely. For requests that need
    /// auth, the key is namespaced by a SHA-256 digest of the credential (see
    /// `HCache.Manager.cacheKey(for:authHeader:)`), and there is no lookup at all without a
    /// credential: the entry of a request sent without one is never stored nor served. The
    /// credential is never logged nor stored.
    /// - Parameters:
    ///   - authHeader: The authorization header sent with the request, or `nil` to resolve it.
    ///   - resolvingAuthHeader: Whether a `nil` header is resolved from the auth provider.
    /// - Returns: The cache key and request headers, or nil if the URL cannot be built or the
    ///   request needs auth and has no credential.
    func cacheLookup(authHeader: HAuthorizationHeader?, resolvingAuthHeader: Bool = true) async -> (key: String, requestHeaders: [String: String]?)? {
        guard let url = compositeURL() else { return nil }

        let resolvedAuthHeader = await resolveAuthHeader(authHeader, enabled: resolvingAuthHeader)
        if needsAuth, resolvedAuthHeader == nil { return nil }

        var headers = await HConfig.shared.defaultHeaderParameters ?? [:]
        if let own = headerParameters {
            headers.merge(own) { _, new in new }
        }
        if let resolvedAuthHeader {
            headers[resolvedAuthHeader.key] = resolvedAuthHeader.value
        }

        let key = HCache.Manager.cacheKey(for: url, authHeader: needsAuth ? resolvedAuthHeader : nil)
        return (key, headers.isEmpty ? nil : headers)
    }

    /// Returns the given authorization header, or resolves it from the configured auth
    /// provider when the request needs auth and resolution is enabled.
    /// - Parameters:
    ///   - authHeader: The already known authorization header, returned as-is when non-nil.
    ///   - enabled: Whether the auth provider may be consulted for a `nil` header.
    /// - Returns: The header to key the cache lookup with, or `nil` for none.
    func resolveAuthHeader(_ authHeader: HAuthorizationHeader?, enabled: Bool = true) async -> HAuthorizationHeader? {
        if let authHeader { return authHeader }
        guard enabled, needsAuth else { return nil }
        return await HConfig.shared.authProvider?.getAuthorizationHeader()
    }

    /// The complete request URL (path and query parameters applied), the base of the cache key.
    /// - Returns: The URL, or nil if it cannot be built.
    func compositeURL() -> URL? {
        try? HURLBuilder.compositeURL(url: url, pathParameters: pathParameters, queryParameters: queryParameters)
    }
}
