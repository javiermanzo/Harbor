//
//  HGetRequestProtocol+Cache.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import Foundation

public extension HGetRequestProtocol {

    /// Retrieves cached data for this request using the associated Model type.
    /// Works with both custom cache and URLCache types.
    /// - Parameter authHeader: The authorization header sent with the request, so
    ///   `Vary: Authorization` entries are keyed by the credential they were stored with.
    ///   When nil and the request needs auth, the header is resolved from the configured
    ///   auth provider.
    /// - Returns: The cached model if found and valid, `nil` otherwise.
    func cache(authHeader: HAuthorizationHeader? = nil) async -> Model? {
        let effectiveCacheType = await effectiveCacheType()

        switch effectiveCacheType {
        case .custom(let config):
            guard let cacheKey = await cacheKey() else { return nil }
            return await HCache.Manager.shared.getCachedData(forKey: cacheKey, type: Model.self, config: config, requestHeaders: await effectiveRequestHeaders(authHeader: authHeader))

        case .urlCache(let urlCache, _):
            guard let urlRequest = await urlRequest() else { return nil }

            if let cached = urlCache.cachedResponse(for: urlRequest) {
                return try? JSONDecoder().decode(Model.self, from: cached.data)
            }
            return nil

        case .disabled:
            return nil
        }
    }

    /// Saves response data to cache for this request.
    /// Only works with custom cache type. For URLCache, the system handles caching automatically.
    /// - Parameters:
    ///   - data: The response data to cache.
    ///   - response: The HTTP response containing cache headers (optional).
    ///   - authHeader: The authorization header sent with the request, so
    ///     `Vary: Authorization` entries are keyed by the credential they were stored with.
    ///     When nil and the request needs auth, the header is resolved from the configured
    ///     auth provider.
    func saveCache(_ data: Data, response: HTTPURLResponse?, authHeader: HAuthorizationHeader? = nil) async {
        if case .custom(let config) = await effectiveCacheType(),
           let cacheKey = await cacheKey() {
            await HCache.Manager.shared.storeData(data, forKey: cacheKey, config: config, response: response, requestHeaders: await effectiveRequestHeaders(authHeader: authHeader))
        }
    }

    /// Returns the stored ETag for this request, if available.
    /// Works with both custom cache and URLCache types.
    func cachedETag() async -> String? {
        switch await effectiveCacheType() {
        case .custom:
            guard let key = await cacheKey() else { return nil }
            return await HCache.Manager.shared.getETag(forKey: key)

        case .urlCache(let urlCache, _):
            guard let urlRequest = await urlRequest(),
                  let cached = urlCache.cachedResponse(for: urlRequest),
                  let httpResponse = cached.response as? HTTPURLResponse else { return nil }
            return httpResponse.value(forHTTPHeaderField: "ETag")

        case .disabled:
            return nil
        }
    }

    /// Clears cached data for this specific request.
    /// Works with both URLCache and custom cache types.
    func clearCache() async {
        guard let cacheKey = await cacheKey() else { return }

        switch await effectiveCacheType() {
        case .urlCache(let urlCache, _):
            // Remove from URLCache
            guard let urlRequest = await urlRequest() else { return }
            urlCache.removeCachedResponse(for: urlRequest)

        case .custom:
            // Remove from custom cache
            await HCache.Manager.shared.removeCachedData(for: cacheKey)

        case .disabled:
            break
        }
    }

    /// Returns the cached body to satisfy a `304 Not Modified` response and refreshes the
    /// stored entry (timestamp, expiration and validators) from the revalidation headers.
    /// - Parameter authHeader: The authorization header sent with the request (see `cache(authHeader:)`).
    func revalidatedCache(response: HTTPURLResponse?, authHeader: HAuthorizationHeader? = nil) async -> Model? {
        switch await effectiveCacheType() {
        case .custom(let config):
            guard let cacheKey = await cacheKey(),
                  let model = await HCache.Manager.shared.getRevalidatableCachedData(forKey: cacheKey, type: Model.self, requestHeaders: await effectiveRequestHeaders(authHeader: authHeader)) else { return nil }
            await HCache.Manager.shared.refreshEntry(forKey: cacheKey, response: response, config: config)
            return model

        case .urlCache(let urlCache, _):
            guard let urlRequest = await urlRequest(),
                  let cached = urlCache.cachedResponse(for: urlRequest) else { return nil }
            return try? JSONDecoder().decode(Model.self, from: cached.data)

        case .disabled:
            return nil
        }
    }

    /// Returns an expired cached body while its `stale-if-error` window still allows serving it.
    /// Only works with custom cache type.
    /// - Parameter authHeader: The authorization header sent with the request (see `cache(authHeader:)`).
    func staleCacheOnError(authHeader: HAuthorizationHeader? = nil) async -> Model? {
        guard case .custom = await effectiveCacheType(),
              let cacheKey = await cacheKey() else { return nil }
        return await HCache.Manager.shared.getStaleOnErrorData(forKey: cacheKey, type: Model.self, requestHeaders: await effectiveRequestHeaders(authHeader: authHeader))
    }
}

extension HGetRequestProtocol {
    /// Returns an expired cached body while its `stale-if-error` window still allows serving it,
    /// keyed only by the headers already present on the request: the auth provider is not
    /// consulted. Only works with custom cache type.
    func staleCacheOnErrorSkippingAuthResolution() async -> Model? {
        guard case .custom = await effectiveCacheType(),
              let cacheKey = await cacheKey() else { return nil }
        return await HCache.Manager.shared.getStaleOnErrorData(forKey: cacheKey, type: Model.self, requestHeaders: await effectiveRequestHeaders(authHeader: nil, resolvingAuthHeader: false))
    }
}

private extension HGetRequestProtocol {

    /// Resolves the effective cache type for this request.
    /// Uses the request-specific cache type if set, otherwise falls back to the global default.
    /// - Returns: The effective `HCache.CacheType` to use for this request.
    func effectiveCacheType() async ->  HCache.CacheType {
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

    /// Resolves the headers that will effectively be sent with this request: the global default
    /// headers merged with the request-specific ones and the authorization header. Used to
    /// evaluate `Vary` consistently with what is actually sent on the wire. When `authHeader`
    /// is nil and the request needs auth, the header is resolved from the configured auth
    /// provider so the vary-key matches the one the network flow stores; without a provider
    /// the lookup proceeds without a header. Pass `resolvingAuthHeader: false` to skip the
    /// provider entirely. The credential is only used for vary-key computation; it is never
    /// logged.
    /// - Parameter authHeader: The authHeader.
    /// - Parameter resolvingAuthHeader: The resolvingAuthHeader.
    func effectiveRequestHeaders(authHeader: HAuthorizationHeader?, resolvingAuthHeader: Bool = true) async -> [String: String]? {
        var headers = await HConfig.shared.defaultHeaderParameters ?? [:]
        if let own = headerParameters {
            headers.merge(own) { _, new in new }
        }
        if let authHeader = await resolveAuthHeader(authHeader, enabled: resolvingAuthHeader) {
            headers[authHeader.key] = authHeader.value
        }
        return headers.isEmpty ? nil : headers
    }

    /// Returns the given authorization header, or resolves it from the configured auth
    /// provider when the request needs auth and resolution is enabled. Never fails: without
    /// a provider the cache path proceeds without a header.
    /// - Parameter authHeader: The authHeader.
    /// - Parameter enabled: The enabled.
    func resolveAuthHeader(_ authHeader: HAuthorizationHeader?, enabled: Bool = true) async -> HAuthorizationHeader? {
        if let authHeader { return authHeader }
        guard enabled, needsAuth else { return nil }
        return await HConfig.shared.authProvider?.getAuthorizationHeader()
    }

    /// Generates a cache key for this request based on the complete URL.
    /// - Returns: The cache key string, or nil if the URL cannot be built.
    func cacheKey() async -> String? {
        let compositeURL: URL? = try? HURLBuilder.compositeURL(url: url,
                                                          pathParameters: pathParameters,
                                                          queryParameters: queryParameters)

        return compositeURL?.absoluteString
    }
}
