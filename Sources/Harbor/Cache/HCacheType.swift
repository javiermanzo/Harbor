//
//  HCacheType.swift
//  Harbor
//
//  Created by Javier Manzo on 20/02/2026.
//

import Foundation

public extension HCache {
    /// The cache a GET request uses. Set the default with `Harbor.setDefaultCacheType(_:)` and
    /// override it per request with `cacheType`.
    enum CacheType: Sendable, Equatable {
        /// Foundation's `URLCache`, which stores and revalidates responses (`ETag`/`304`)
        /// transparently following the response's HTTP caching headers.
        ///
        /// `URLCache` keys entries by URL only: unlike `.custom`, entries are not namespaced by
        /// credential, neither for `needsAuth` requests nor for credentials sent in headers
        /// (`Authorization`, `X-API-Key`, ...). Use `.custom` when responses depend on the
        /// credential, and call `Harbor.clearAllCache()` on logout.
        /// - Parameters:
        ///   - urlCache: The URLCache to use. Defaults to `URLCache.shared`.
        ///   - requestCachePolicy: The cache policy of the requests. Defaults to `.useProtocolCachePolicy`.
        case urlCache(urlCache: URLCache = .shared, requestCachePolicy: NSURLRequest.CachePolicy = .useProtocolCachePolicy)

        /// Harbor's own memory + disk cache (LRU), with a fallback expiration and size limits. It
        /// honors `Cache-Control`, `Expires`, `Age`, `Vary`, `stale-while-revalidate` and
        /// `stale-if-error`, and revalidates entries with their `ETag`/`Last-Modified`. Entries are
        /// namespaced by the credential a request is sent with: the auth provider's header and any
        /// sensitive header (`Authorization`, `Proxy-Authorization`, `Cookie`, `X-API-Key`, ...)
        /// set in the default or request headers.
        case custom(Configuration)

        /// No caching: every request reaches the network.
        case disabled

        /// Whether caching is enabled for this type. Used by tests.
        var isCachingEnabled: Bool {
            switch self {
            case .urlCache, .custom:
                return true
            case .disabled:
                return false
            }
        }

        // MARK: - Equatable

        /// `.urlCache` cases compare the cache by identity and the policy by value.
        public static func == (lhs: CacheType, rhs: CacheType) -> Bool {
            switch (lhs, rhs) {
            case (.urlCache(let lCache, let lPolicy), .urlCache(let rCache, let rPolicy)):
                return ObjectIdentifier(lCache) == ObjectIdentifier(rCache) &&
                       lPolicy == rPolicy
            case (.disabled, .disabled):
                return true
            case (.custom(let lConfig), .custom(let rConfig)):
                return lConfig == rConfig
            default:
                return false
            }
        }
    }
}
