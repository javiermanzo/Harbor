//
//  HCacheEntry.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import Foundation

// MARK: - Cache Entry Metadata

/// Shared metadata and expiration logic for cache entries, in memory or on disk.
protocol HCacheEntryInfo {
    /// When the entry was stored.
    var timestamp: Date { get }
    /// Lifetime in seconds resolved at store time. Overrides the max age passed by the caller.
    var expirationTime: TimeInterval? { get }
    /// Entries marked always stale (e.g. `Cache-Control: no-cache`) are never served without revalidation,
    /// but are kept as a source of validators (ETag / Last-Modified).
    var alwaysStale: Bool { get }
}

extension HCacheEntryInfo {
    /// Checks if the cache entry is expired based on max age or stored expiration time.
    /// - Parameter maxAge: Maximum age in seconds. Used only when the entry has no stored expiration time.
    /// - Returns: true if expired, false otherwise.
    func isExpired(maxAge: TimeInterval?) -> Bool {
        if alwaysStale { return true }
        let effectiveMaxAge = expirationTime ?? maxAge
        guard let maxAge = effectiveMaxAge else { return false }
        return Date().timeIntervalSince(timestamp) > maxAge
    }
}

// MARK: - Cache Entry Implementation

extension HCache.Manager {
    /// In-memory (L1) cache entry containing data, metadata and revalidation validators.
    final class Entry: Sendable, HCacheEntryInfo {
        /// The raw cached payload data.
        let data: Data
        /// When the entry was stored.
        let timestamp: Date
        /// Expiration lifetime in seconds.
        let expirationTime: TimeInterval?
        /// HTTP ETag validator string.
        let etag: String?
        /// HTTP Last-Modified validator string.
        let lastModified: String?
        /// Raw `Vary` header value of the stored response, if any.
        let vary: String?
        /// Resolved values of the `Vary` header fields taken from the request that stored the entry.
        let varyKey: String?
        /// Whether the entry is marked always stale.
        let alwaysStale: Bool
        /// Whether the entry must always be revalidated after expiration.
        let mustRevalidate: Bool
        /// Window in seconds (from `stale-if-error`) during which the expired entry may be served on errors.
        let staleIfError: TimeInterval?

        /// Initializes an in-memory cache entry.
        init(
            data: Data,
            timestamp: Date,
            expirationTime: TimeInterval? = nil,
            etag: String? = nil,
            lastModified: String? = nil,
            vary: String? = nil,
            varyKey: String? = nil,
            alwaysStale: Bool = false,
            mustRevalidate: Bool = false,
            staleIfError: TimeInterval? = nil
        ) {
            self.data = data
            self.timestamp = timestamp
            self.expirationTime = expirationTime
            self.etag = etag
            self.lastModified = lastModified
            self.vary = vary
            self.varyKey = varyKey
            self.alwaysStale = alwaysStale
            self.mustRevalidate = mustRevalidate
            self.staleIfError = staleIfError
        }

        /// Whether the entry carries a validator (ETag or Last-Modified) usable for conditional requests.
        var hasValidator: Bool {
            return etag != nil || lastModified != nil
        }

        /// Whether the entry can be served for a request with the given vary key.
        /// `Vary: *` entries are never served directly.
        /// - Parameter currentVaryKey: The vary key computed from current request headers.
        /// - Returns: `true` if the entry matches the vary key, `false` otherwise.
        func matchesVary(_ currentVaryKey: String?) -> Bool {
            if varyKey == "*" { return false }
            return varyKey == currentVaryKey
        }

        /// Vary check used for revalidation: `Vary: *` entries cannot be served directly,
        /// but their validators can still be used in conditional requests.
        /// - Parameter currentVaryKey: The vary key computed from current request headers.
        /// - Returns: `true` if the entry matches or is a wildcard, `false` otherwise.
        func matchesVaryOrWildcard(_ currentVaryKey: String?) -> Bool {
            if varyKey == "*" { return true }
            return varyKey == currentVaryKey
        }
    }
}
