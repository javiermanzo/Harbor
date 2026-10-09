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
    /// - Parameters:
    ///   - maxAge: Maximum age in seconds. Used only when the entry has no stored expiration time.
    ///   - grace: Extra seconds past the freshness lifetime during which the entry still counts
    ///     as servable (e.g. the `stale-while-revalidate` window). Default: `0`.
    /// - Returns: true if expired, false otherwise.
    func isExpired(maxAge: TimeInterval?, grace: TimeInterval = 0) -> Bool {
        if alwaysStale { return true }
        let effectiveMaxAge = expirationTime ?? maxAge
        guard let maxAge = effectiveMaxAge else { return false }
        return Date().timeIntervalSince(timestamp) > maxAge + grace
    }
}

// MARK: - Persisted Metadata

extension HCache {
    /// Metadata of a cache entry: freshness, validators, `Vary` and stale-serving directives.
    /// It is the JSON header of the on-disk format, so it never holds the response body nor
    /// any raw request header value (the `Vary` key is stored hashed).
    struct EntryMetadata: Codable, Sendable, Equatable, HCacheEntryInfo {
        /// Schema version of the current on-disk format. Files with any other version are discarded.
        ///
        /// - 1: single JSON document with a base64 body and a plain-text vary key.
        /// - 2: length-prefixed JSON metadata header followed by the raw body; hashed vary key.
        static let currentVersion = 2

        /// The version of the schema when this entry was written.
        var version: Int = Self.currentVersion
        /// The date the entry was stored or refreshed.
        var timestamp: Date
        /// The freshness lifetime in seconds relative to `timestamp`.
        var expirationTime: TimeInterval?
        /// ETag header value stored for future If-None-Match requests.
        var etag: String?
        /// Last-Modified header value stored for future If-Modified-Since requests.
        var lastModified: String?
        /// The original Vary header from the response.
        var vary: String?
        /// SHA-256 digest of the request values of the `Vary` header fields (`"*"` for `Vary: *`).
        var varyKey: String?
        /// Whether the entry is always considered stale (e.g. `no-cache`).
        var alwaysStale: Bool = false
        /// Whether the entry must always be revalidated after expiration.
        var mustRevalidate: Bool = false
        /// The grace period to serve this stale entry if a new request fails.
        var staleIfError: TimeInterval?
        /// The window (from `stale-while-revalidate`) past the freshness lifetime during which
        /// the entry may still be served from cache while it is revalidated remotely.
        var staleWhileRevalidate: TimeInterval?

        /// Whether this entry has either an ETag or Last-Modified validator.
        var hasValidator: Bool {
            return etag != nil || lastModified != nil
        }

        /// The `stale-while-revalidate` window that applies to direct cache reads. Entries that
        /// must be revalidated never get one.
        var servableStaleWindow: TimeInterval {
            guard !alwaysStale, !mustRevalidate else { return 0 }
            return max(staleWhileRevalidate ?? 0, 0)
        }

        /// Whether an expired entry can be deleted: it has no validator to revalidate it with, and
        /// neither its `stale-while-revalidate` nor its `stale-if-error` window still allows
        /// serving it.
        /// - Parameter maxAge: Freshness lifetime used when the entry has no stored expiration time.
        func isDiscardable(maxAge: TimeInterval?) -> Bool {
            guard !hasValidator, isExpired(maxAge: maxAge, grace: servableStaleWindow) else { return false }
            if !mustRevalidate, let window = staleIfError, let freshness = expirationTime,
               Date().timeIntervalSince(timestamp) - freshness <= window {
                return false
            }
            return true
        }

        /// Whether the entry can be served for a request with the given vary key.
        /// `Vary: *` entries are never served directly.
        /// - Parameter currentVaryKey: The vary key computed from current request headers.
        func matchesVary(_ currentVaryKey: String?) -> Bool {
            if varyKey == "*" { return false }
            return varyKey == currentVaryKey
        }

        /// Vary check used for revalidation: `Vary: *` entries cannot be served directly,
        /// but their validators can still be used in conditional requests.
        /// - Parameter currentVaryKey: The vary key computed from current request headers.
        func matchesVaryOrWildcard(_ currentVaryKey: String?) -> Bool {
            if varyKey == "*" { return true }
            return varyKey == currentVaryKey
        }
    }
}

// MARK: - Cache Entry Implementation

extension HCache.Manager {
    /// In-memory (L1) cache entry: the raw body plus its metadata.
    final class Entry: Sendable, HCacheEntryInfo {
        /// The raw cached payload data.
        let data: Data
        /// Freshness, validators and directives of the entry.
        let metadata: HCache.EntryMetadata

        /// Initializes an in-memory cache entry.
        init(data: Data, metadata: HCache.EntryMetadata) {
            self.data = data
            self.metadata = metadata
        }

        /// When the entry was stored.
        var timestamp: Date { metadata.timestamp }
        /// Expiration lifetime in seconds.
        var expirationTime: TimeInterval? { metadata.expirationTime }
        /// Whether the entry is marked always stale.
        var alwaysStale: Bool { metadata.alwaysStale }
        /// HTTP ETag validator string.
        var etag: String? { metadata.etag }
        /// HTTP Last-Modified validator string.
        var lastModified: String? { metadata.lastModified }
        /// Whether the entry carries a validator (ETag or Last-Modified) usable for conditional requests.
        var hasValidator: Bool { metadata.hasValidator }
    }
}
