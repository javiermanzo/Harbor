//
//  HCache+Manager.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import Foundation

/// Namespace for caching-related types and functionality.
public enum HCache {}

extension HCache {
    /// Two-level (memory + disk) cache manager with granular expiration control and
    /// HTTP revalidation support (ETag / Last-Modified).
    ///
    /// Cached bodies are decoded by the caller-provided `decode` closure (the request's
    /// `parseData(data:model:)`), so requests with a custom parser read back exactly what the
    /// network flow decodes. A body that cannot be decoded is a miss for that request but is
    /// kept: another request type sharing the URL may still decode it.
    ///
    /// On disk each entry is a single file: a length-prefixed JSON metadata header followed by
    /// the raw body (see `DiskCodec`), so metadata can be read without loading the body. Disk
    /// usage is tracked by an in-memory index built lazily from the directory, and eviction is
    /// least-recently-used: reads refresh the entry's access time.
    ///
    /// Marked `@unchecked Sendable`: memory and index access is serialized by
    /// `@HRequestManagerActor`, disk access by `diskQueue` (writes and deletes run under a
    /// barrier), and `NSCache` is internally thread-safe.
    @HRequestManagerActor
    final class Manager: @unchecked Sendable {

        /// Shared instance of the cache manager.
        static let shared = Manager()

        /// Minimum interval between two on-disk access-time updates of the same entry. Reads in
        /// between only refresh the in-memory index, which drives eviction within the session.
        static let accessTimePersistInterval: TimeInterval = 60

        /// Fast in-memory cache (L1)
        private let memoryCache = NSCache<NSString, Entry>()

        /// Cache directory for persistence (L2)
        let cacheDirectory: URL

        /// Concurrent queue for disk I/O. Reads run concurrently; writes and deletes run under a barrier.
        private let diskQueue = DispatchQueue(label: "harbor.cache.disk", qos: .utility, attributes: .concurrent)

        /// Token to track cache clearance cycles, preventing L1/L2 sync races.
        private var cacheClearToken = 0

        /// Size and last access of every file on disk. `nil` until first needed; built from a
        /// single directory listing instead of listing the directory on every write.
        private var diskIndex: DiskIndex?

        /// In-flight index build, shared by concurrent writers.
        private var diskIndexBuild: Task<Void, Never>?

        /// Last time each entry's access time was persisted on disk (or the entry was written),
        /// keyed by file name. Throttles the on-disk access-time updates independently of the
        /// disk index, which may not exist yet.
        private var lastPersistedAccess: [String: Date] = [:]

        /// Bound of `lastPersistedAccess`; past it, records older than the throttle interval are pruned.
        private static let maxPersistedAccessRecords = 1024

        /// Number of on-disk access-time updates scheduled. Intended for testing.
        private(set) var diskAccessTouchCount = 0

        /// Memory capacity of the global default cache configuration (0 when it is not `.custom`).
        private var defaultMemoryCapacity: Int

        /// Largest memory capacity requested by any configuration used to store an entry since the
        /// global default was last set. The memory limit never shrinks because of a smaller
        /// per-request configuration (no last-writer-wins).
        private var largestRequestedMemoryCapacity = 0

        private init() {
            // 1. Setup cache directory safely in Library/Caches
            if let systemCacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                self.cacheDirectory = systemCacheDir.appendingPathComponent("HarborCache", isDirectory: true)
            } else {
                self.cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("HarborCache", isDirectory: true)
            }

            // 2. Create directory
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

            // 3. Configure NSCache limits: bounded by cost (body bytes) only, no fixed count.
            self.defaultMemoryCapacity = Configuration().memoryCacheCapacityInBytes
            memoryCache.totalCostLimit = defaultMemoryCapacity

            // 4. Discard expired and outdated files in the background. Only metadata headers are
            //    read, off the actor and without blocking disk reads or writes.
            Task(priority: .background) { @HRequestManagerActor [weak self] in
                await self?.performStartupCleanup()
            }
        }

        // MARK: - Keys

        /// Builds the cache key for a request URL. Requests that need auth are namespaced by a
        /// SHA-256 digest of the authorization header they are sent with, so an entry stored
        /// for one credential can never be read with another. The raw credential is never part
        /// of the key.
        /// - Parameters:
        ///   - url: The composite request URL.
        ///   - authHeader: The authorization header sent with an authenticated request, or `nil`
        ///     for requests that do not need auth or are sent without credentials.
        /// - Returns: The cache key string.
        nonisolated static func cacheKey(for url: URL, authHeader: HAuthorizationHeader?) -> String {
            guard let authHeader else { return url.absoluteString }
            let credential = "\(authHeader.key.lowercased()):\(authHeader.value)"
            return "\(url.absoluteString)#harbor-auth=\(credential.sha256Hex)"
        }

        // MARK: - Public API

        /// Retrieves cached data by key (for custom cache type).
        ///
        /// Expired entries are never served, except within their `stale-while-revalidate`
        /// window. Entries that carry validators (ETag / Last-Modified) — including `no-cache`
        /// entries, which are always stale — are kept as a source of validators; entries
        /// without validators are evicted on expiration.
        /// - Parameters:
        ///   - key: The cache key string.
        ///   - config: The cache configuration containing expiration limits.
        ///   - requestHeaders: Optional HTTP request headers used for `Vary` validation.
        ///   - decode: Decodes the cached body (the request's `parseData(data:model:)`).
        /// - Returns: Decoded model if found and valid, `nil` otherwise.
        func getCachedData<T: HModel>(forKey key: String, config: HCache.Configuration, requestHeaders: [String: String]? = nil, decode: @Sendable (Data) throws -> T) async -> T? {
            let nsKey = NSString(string: key)

            // L1: Memory Cache
            if let entry = memoryCache.object(forKey: nsKey) {
                let metadata = entry.metadata
                if metadata.isExpired(maxAge: config.expirationTime, grace: metadata.servableStaleWindow) {
                    if !metadata.hasValidator { memoryCache.removeObject(forKey: nsKey) }
                    return nil
                }
                guard metadata.matchesVary(Self.varyKey(for: metadata.vary, requestHeaders: requestHeaders)) else { return nil }
                noteAccess(forKey: key)
                return decodeEntry(entry.data, decode: decode)
            }

            // L2: Disk Cache
            let token = cacheClearToken
            guard let (metadata, body) = await loadDiskEntry(forKey: key) else { return nil }

            // Vary mismatch: the stored variant cannot satisfy this request. It is a miss,
            // but the entry is kept — another request may still match it.
            guard metadata.matchesVary(Self.varyKey(for: metadata.vary, requestHeaders: requestHeaders)) else {
                return nil
            }

            // Expiration: keep entries that can still be revalidated, evict the rest.
            if metadata.isExpired(maxAge: config.expirationTime, grace: metadata.servableStaleWindow) {
                if !metadata.hasValidator {
                    await removeDiskData(forKey: key)
                }
                return nil
            }

            guard let model = decodeEntry(body, decode: decode) else { return nil }

            // A clearAllCache that ran while the disk read was suspended wins: the entry is
            // neither served nor promoted back into memory.
            guard token == cacheClearToken else { return nil }

            // Promote to Memory Cache
            memoryCache.setObject(Entry(data: body, metadata: metadata), forKey: nsKey, cost: body.count)
            noteAccess(forKey: key)

            return model
        }

        /// Returns the cached body for a key even when the entry is expired, as long as it carries a
        /// validator (ETag / Last-Modified). Used to satisfy a `304 Not Modified` revalidation.
        /// - Parameters:
        ///   - key: The cache key string.
        ///   - requestHeaders: Optional HTTP request headers used for `Vary` validation.
        ///   - decode: Decodes the cached body (the request's `parseData(data:model:)`).
        /// - Returns: Decoded model if revalidatable, `nil` otherwise (including a body this
        ///   request cannot decode, which is kept).
        func getRevalidatableCachedData<T: HModel>(forKey key: String, requestHeaders: [String: String]? = nil, decode: @Sendable (Data) throws -> T) async -> T? {
            if let entry = memoryCache.object(forKey: NSString(string: key)) {
                let metadata = entry.metadata
                guard metadata.hasValidator, metadata.matchesVaryOrWildcard(Self.varyKey(for: metadata.vary, requestHeaders: requestHeaders)) else { return nil }
                noteAccess(forKey: key)
                return decodeEntry(entry.data, decode: decode)
            }

            guard let (metadata, body) = await loadDiskEntry(forKey: key),
                  metadata.hasValidator,
                  metadata.matchesVaryOrWildcard(Self.varyKey(for: metadata.vary, requestHeaders: requestHeaders)) else {
                return nil
            }

            noteAccess(forKey: key)
            return decodeEntry(body, decode: decode)
        }

        /// Returns an expired entry when its `stale-if-error` window still allows serving it.
        /// Entries marked `must-revalidate` are never served stale.
        /// - Parameters:
        ///   - key: The cache key string.
        ///   - requestHeaders: Optional HTTP request headers used for `Vary` validation.
        ///   - decode: Decodes the cached body (the request's `parseData(data:model:)`).
        /// - Returns: Decoded stale model if within `stale-if-error` grace period, `nil` otherwise.
        func getStaleOnErrorData<T: HModel>(forKey key: String, requestHeaders: [String: String]? = nil, decode: @Sendable (Data) throws -> T) async -> T? {
            if let entry = memoryCache.object(forKey: NSString(string: key)) {
                guard Self.isServableOnError(entry.metadata, requestHeaders: requestHeaders) else { return nil }
                return decodeEntry(entry.data, decode: decode)
            }

            guard let (metadata, body) = await loadDiskEntry(forKey: key),
                  Self.isServableOnError(metadata, requestHeaders: requestHeaders) else {
                return nil
            }
            return decodeEntry(body, decode: decode)
        }

        /// Whether an entry satisfies the `stale-if-error` conditions for the given request headers.
        /// - Parameters:
        ///   - metadata: The entry metadata.
        ///   - requestHeaders: Optional HTTP request headers used for `Vary` validation.
        private static func isServableOnError(_ metadata: HCache.EntryMetadata, requestHeaders: [String: String]?) -> Bool {
            guard !metadata.mustRevalidate,
                  metadata.isExpired(maxAge: nil),
                  let window = metadata.staleIfError,
                  let freshness = metadata.expirationTime,
                  Date().timeIntervalSince(metadata.timestamp) - freshness <= window else { return false }
            return metadata.matchesVary(Self.varyKey(for: metadata.vary, requestHeaders: requestHeaders))
        }

        /// Stores data by key (for custom cache type), honoring the response cache directives.
        ///
        /// - `no-store` responses are not persisted at all, and any previous entry for the key
        ///   is evicted (it no longer reflects the server's representation). The same applies
        ///   to bodies larger than `maxObjectSizeInMBs`.
        /// - `no-cache` responses are persisted but marked always stale, so they are never
        ///   served without revalidation while their validators are preserved.
        /// - `Vary` is stored (as a SHA-256 digest of the request values) and enforced on reads;
        ///   `Vary: *` entries are never served directly.
        /// - Parameters:
        ///   - data: The response body to store.
        ///   - key: The cache key string.
        ///   - config: The cache configuration (size limits and fallback expiration).
        ///   - response: The HTTP response whose headers drive expiration, validators and `Vary`.
        ///   - requestHeaders: The request headers the response was obtained with, for the `Vary` key.
        func storeData(_ data: Data, forKey key: String, config: HCache.Configuration, response: HTTPURLResponse?, requestHeaders: [String: String]? = nil) async {
            registerMemoryCapacity(of: config)

            let directives = response?.value(forHTTPHeaderField: "Cache-Control").map { Self.parseCacheControlDirectives($0) }

            guard data.count <= config.maxObjectSizeInBytes, directives?.noStore != true else {
                await removeCachedData(for: key)
                return
            }

            let vary = response?.value(forHTTPHeaderField: "Vary")
            let varyKey = Self.varyKey(for: vary, requestHeaders: requestHeaders)

            let metadata = HCache.EntryMetadata(
                timestamp: Date(),
                expirationTime: calculateEffectiveExpirationTime(fromResponse: response, fallbackTime: config.expirationTime),
                etag: response?.value(forHTTPHeaderField: "ETag"),
                lastModified: response?.value(forHTTPHeaderField: "Last-Modified"),
                vary: vary,
                varyKey: varyKey,
                alwaysStale: directives?.noCache == true || varyKey == "*",
                mustRevalidate: directives?.mustRevalidate == true || directives?.proxyRevalidate == true,
                staleIfError: directives?.staleIfError.map { TimeInterval($0) },
                staleWhileRevalidate: directives?.staleWhileRevalidate.map { TimeInterval($0) }
            )

            await persist(Entry(data: data, metadata: metadata), forKey: key, diskCapacity: config.diskCacheCapacityInBytes, token: cacheClearToken)
        }

        /// Refreshes the stored entry after a `304 Not Modified`: updates the timestamp and the
        /// expiration from the response headers, and merges any updated validators.
        /// - Parameters:
        ///   - key: The cache key string.
        ///   - response: The 304 response; headers it omits keep the stored values.
        ///   - config: The cache configuration providing the fallback expiration and disk capacity.
        func refreshEntry(forKey key: String, response: HTTPURLResponse?, config: HCache.Configuration) async {
            let token = cacheClearToken

            var current = memoryCache.object(forKey: NSString(string: key))
            if current == nil, let (metadata, body) = await loadDiskEntry(forKey: key) {
                current = Entry(data: body, metadata: metadata)
            }

            // Nothing to refresh, or the cache was cleared while the disk read was suspended.
            guard let entry = current, token == cacheClearToken else { return }

            let directives = response?.value(forHTTPHeaderField: "Cache-Control").map { Self.parseCacheControlDirectives($0) }

            // Headers absent from the 304 response retain the values of the stored entry.
            var metadata = entry.metadata
            metadata.version = HCache.EntryMetadata.currentVersion
            metadata.timestamp = Date()
            metadata.expirationTime = calculateEffectiveExpirationTime(fromResponse: response, fallbackTime: entry.expirationTime ?? config.expirationTime)
            metadata.etag = response?.value(forHTTPHeaderField: "ETag") ?? entry.etag
            metadata.lastModified = response?.value(forHTTPHeaderField: "Last-Modified") ?? entry.lastModified
            metadata.alwaysStale = (directives?.noCache ?? entry.alwaysStale) || metadata.varyKey == "*"
            metadata.mustRevalidate = directives.map { $0.mustRevalidate || $0.proxyRevalidate } ?? entry.metadata.mustRevalidate
            metadata.staleIfError = directives?.staleIfError.map { TimeInterval($0) } ?? entry.metadata.staleIfError
            metadata.staleWhileRevalidate = directives?.staleWhileRevalidate.map { TimeInterval($0) } ?? entry.metadata.staleWhileRevalidate

            await persist(Entry(data: entry.data, metadata: metadata), forKey: key, diskCapacity: config.diskCacheCapacityInBytes, token: token)
        }

        /// Returns the stored validators (ETag and Last-Modified) for the given cache key, if available.
        /// Entries whose `Vary` does not match the request headers are ignored. Only the
        /// metadata header is read from disk.
        /// - Parameters:
        ///   - key: The cache key string.
        ///   - requestHeaders: Optional HTTP request headers used for `Vary` validation.
        func getValidators(forKey key: String, requestHeaders: [String: String]? = nil) async -> (etag: String?, lastModified: String?) {
            let metadata: HCache.EntryMetadata
            if let entry = memoryCache.object(forKey: NSString(string: key)) {
                metadata = entry.metadata
            } else if let diskMetadata = await readDiskMetadata(forKey: key) {
                metadata = diskMetadata
            } else {
                return (nil, nil)
            }
            guard metadata.matchesVaryOrWildcard(Self.varyKey(for: metadata.vary, requestHeaders: requestHeaders)) else { return (nil, nil) }
            return (metadata.etag, metadata.lastModified)
        }

        /// Returns the stored ETag for the given cache key, if available. Only the metadata
        /// header is read from disk.
        /// - Parameter key: The cache key string.
        func getETag(forKey key: String) async -> String? {
            if let entry = memoryCache.object(forKey: NSString(string: key)) {
                return entry.etag
            }
            return await readDiskMetadata(forKey: key)?.etag
        }

        /// Clears all cached data, waiting until disk cleanup completes.
        func clearAllCache() async {
            cacheClearToken &+= 1
            memoryCache.removeAllObjects()
            diskIndex = DiskIndex()
            lastPersistedAccess.removeAll()

            let dir = self.cacheDirectory
            await withCheckedContinuation { continuation in
                diskQueue.async(flags: .barrier) {
                    try? FileManager.default.removeItem(at: dir)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    continuation.resume()
                }
            }
        }

        /// Removes specific cached data, waiting until disk cleanup completes.
        /// - Parameter key: The cache key string of the entry to remove.
        func removeCachedData(for key: String) async {
            memoryCache.removeObject(forKey: NSString(string: key))
            await removeDiskData(forKey: key)
        }

        /// Applies the memory limit derived from the global default cache type. Called whenever
        /// the default cache type changes; per-request configurations seen afterwards can only
        /// raise the limit.
        /// - Parameter cacheType: The new global default cache type.
        func applyDefaultCacheType(_ cacheType: HCache.CacheType) {
            if case .custom(let config) = cacheType {
                defaultMemoryCapacity = config.memoryCacheCapacityInBytes
            } else {
                defaultMemoryCapacity = 0
            }
            largestRequestedMemoryCapacity = 0
            updateMemoryCostLimit()
        }

        /// Waits until all pending disk operations complete. Intended for testing.
        func waitForPendingDiskOperations() async {
            await withCheckedContinuation { continuation in
                diskQueue.async(flags: .barrier) {
                    continuation.resume()
                }
            }
        }

        /// Current cost limit of the memory cache. Intended for testing.
        var memoryCacheCostLimit: Int {
            memoryCache.totalCostLimit
        }

        /// Current count limit of the memory cache (0 means unlimited). Intended for testing.
        var memoryCacheCountLimit: Int {
            memoryCache.countLimit
        }

        /// Total bytes tracked by the disk index, or `nil` when it has not been built. Intended for testing.
        var diskIndexTotalSize: Int? {
            diskIndex?.totalSize
        }

        /// Simulates a relaunch: drops the memory cache, the disk index and the access-time
        /// throttle, keeping the files on disk. Intended for testing.
        func simulateRelaunch() {
            memoryCache.removeAllObjects()
            diskIndex = nil
            lastPersistedAccess.removeAll()
        }

        /// Runs the startup cleanup and waits for it. Intended for testing.
        func runStartupCleanup() async {
            await performStartupCleanup()
        }

        // MARK: - Memory Limits

        /// Raises the memory limit when a configuration asks for more than the current one.
        private func registerMemoryCapacity(of config: HCache.Configuration) {
            guard config.memoryCacheCapacityInBytes > largestRequestedMemoryCapacity else { return }
            largestRequestedMemoryCapacity = config.memoryCacheCapacityInBytes
            updateMemoryCostLimit()
        }

        private func updateMemoryCostLimit() {
            memoryCache.totalCostLimit = max(defaultMemoryCapacity, largestRequestedMemoryCapacity)
        }

        // MARK: - Decoding

        /// Decodes a cached body. A body that cannot be decoded is a miss for this request only;
        /// the entry is never evicted because of it: different request types (models or
        /// parsers) may share a URL, and an entry valid for one must survive a read by another.
        /// An entry nobody can decode anymore heals itself: the miss (or, for a revalidation,
        /// the unconditional refetch after a `304`) brings a full response that replaces it.
        private func decodeEntry<T>(_ data: Data, decode: @Sendable (Data) throws -> T) -> T? {
            do {
                return try decode(data)
            } catch {
                HLogger.log("A cached body cannot be decoded for this request; treating it as a miss", error: error, level: .debug)
                return nil
            }
        }

        // MARK: - Expiration Logic

        /// Resolves the effective expiration time honoring the response cache directives
        /// (`s-maxage` and `max-age` take precedence over `Expires`, which takes precedence
        /// over the configured fallback).
        ///
        /// The lifetime is reduced by the response `Age` header (time already spent in upstream
        /// caches), and `Expires` is measured from the response `Date` header when present so
        /// a skewed local clock does not stretch or shrink it.
        /// - Parameters:
        ///   - response: The HTTP response carrying the cache headers, if any.
        ///   - fallbackTime: The configured expiration used when the response gives no lifetime.
        /// - Returns: The lifetime in seconds, or `nil` for no expiration.
        func calculateEffectiveExpirationTime(fromResponse response: HTTPURLResponse?, fallbackTime: TimeInterval?) -> TimeInterval? {
            guard let response = response else { return fallbackTime }
            guard let lifetime = Self.freshnessLifetime(of: response) else { return fallbackTime }
            return max(lifetime - Self.ageHeaderValue(of: response), 0)
        }

        /// Explicit freshness lifetime of a response (`s-maxage`, `max-age`, or `Expires`
        /// relative to `Date`), without accounting for its age.
        private static func freshnessLifetime(of response: HTTPURLResponse, now: Date = Date()) -> TimeInterval? {
            if let cacheControl = response.value(forHTTPHeaderField: "Cache-Control") {
                let directives = Self.parseCacheControlDirectives(cacheControl)
                if let sMaxAge = directives.sMaxAge { return TimeInterval(sMaxAge) }
                if let maxAge = directives.maxAge { return TimeInterval(maxAge) }
            }

            if let expiresString = response.value(forHTTPHeaderField: "Expires"),
               let expiresDate = Self.parseHTTPDate(expiresString) {
                let reference = response.value(forHTTPHeaderField: "Date").flatMap { Self.parseHTTPDate($0) } ?? now
                return max(expiresDate.timeIntervalSince(reference), 0)
            }
            return nil
        }

        /// The response `Age` header in seconds, or 0 when absent or malformed.
        private static func ageHeaderValue(of response: HTTPURLResponse) -> TimeInterval {
            guard let value = response.value(forHTTPHeaderField: "Age")?.trimmingCharacters(in: .whitespaces),
                  let age = Int(value), age > 0 else { return 0 }
            return TimeInterval(age)
        }

        /// Whether a response stored in a `URLCache` may be served directly. A stored response
        /// is servable unless its headers mark it as explicitly stale, applying the same
        /// directive parsing as the custom cache:
        /// - `Cache-Control: no-cache` / `no-store` are never served;
        /// - an explicit lifetime (`s-maxage`, `max-age`, or `Expires` relative to `Date`) is
        ///   stale once the current age (time since `Date` plus `Age`) reaches it, extended by
        ///   `stale-while-revalidate` unless the response must be revalidated;
        /// - without an explicit lifetime, the 10% `Last-Modified` heuristic applies when a
        ///   `Date` header is present.
        ///
        /// A response without a `Date` header cannot be aged, so only its `Age` header counts
        /// toward the current age (a `max-age` it has not consumed keeps it servable). A
        /// response with no freshness information at all is served: `URLCache` itself decided
        /// to store it.
        /// - Parameters:
        ///   - response: The cached response.
        ///   - now: The current date.
        static func isFresh(urlCacheResponse response: HTTPURLResponse, now: Date = Date()) -> Bool {
            let directives = response.value(forHTTPHeaderField: "Cache-Control").map { Self.parseCacheControlDirectives($0) } ?? CacheControlDirectives()
            guard !directives.noCache, !directives.noStore else { return false }

            let date = response.value(forHTTPHeaderField: "Date").flatMap { Self.parseHTTPDate($0) }
            let lifetime: TimeInterval
            if let explicit = Self.freshnessLifetime(of: response, now: now) {
                lifetime = explicit
            } else if let date, let lastModified = response.value(forHTTPHeaderField: "Last-Modified").flatMap({ Self.parseHTTPDate($0) }) {
                lifetime = max(date.timeIntervalSince(lastModified), 0) * 0.1
            } else {
                return true
            }

            let currentAge = (date.map { max(now.timeIntervalSince($0), 0) } ?? 0) + Self.ageHeaderValue(of: response)
            let mustRevalidate = directives.mustRevalidate || directives.proxyRevalidate
            let grace = mustRevalidate ? 0 : TimeInterval(max(directives.staleWhileRevalidate ?? 0, 0))
            return currentAge < lifetime + grace
        }

        /// Parses a `Cache-Control` header into its directives. Header parsing is case-insensitive
        /// and unknown or malformed directives are ignored.
        /// - Parameter cacheControl: The raw `Cache-Control` header value.
        static func parseCacheControlDirectives(_ cacheControl: String) -> CacheControlDirectives {
            let directives = cacheControl.lowercased().components(separatedBy: ",")
            var result = CacheControlDirectives()

            for directive in directives {
                let trimmed = directive.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("s-maxage=") {
                    result.sMaxAge = Self.parseDeltaSeconds(String(trimmed.dropFirst(9)))
                } else if trimmed.hasPrefix("max-age=") {
                    result.maxAge = Self.parseDeltaSeconds(String(trimmed.dropFirst(8)))
                } else if trimmed.hasPrefix("stale-while-revalidate=") {
                    result.staleWhileRevalidate = Self.parseDeltaSeconds(String(trimmed.dropFirst(23)))
                } else if trimmed.hasPrefix("stale-if-error=") {
                    result.staleIfError = Self.parseDeltaSeconds(String(trimmed.dropFirst(15)))
                } else {
                    switch trimmed {
                    case "no-cache": result.noCache = true
                    case "no-store": result.noStore = true
                    case "must-revalidate": result.mustRevalidate = true
                    case "proxy-revalidate": result.proxyRevalidate = true
                    case "public": result.isPublic = true
                    case "private": result.isPrivate = true
                    default: break
                    }
                }
            }
            return result
        }

        /// Parses a delta-seconds directive value, tolerating the quoted-string form
        /// (`max-age="60"`) allowed for field values.
        private static func parseDeltaSeconds(_ value: String) -> Int? {
            let unquoted = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return Int(unquoted)
        }

        /// HTTP-date formatters for the three formats allowed by RFC 9110 (IMF-fixdate, RFC 850, asctime),
        /// one instance per format so the date format is never mutated between parses.
        private static let httpDateFormatters: [DateFormatter] = {
            let formats = [
                "EEE, dd MMM yyyy HH:mm:ss zzz",
                "EEEE, dd-MMM-yy HH:mm:ss zzz",
                "EEE MMM d HH:mm:ss yyyy"
            ]
            return formats.map { format in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = format
                return formatter
            }
        }()

        /// Parses an HTTP-date header value (`Expires`, `Last-Modified`, `Date`).
        /// - Parameter string: The header value, in any of the three RFC 9110 date formats.
        static func parseHTTPDate(_ string: String) -> Date? {
            for formatter in httpDateFormatters {
                if let date = formatter.date(from: string) { return date }
            }
            return nil
        }

        /// Resolves the values of the header fields listed in a `Vary` header from the given
        /// request headers, producing a comparable key. Returns `"*"` when the vary header
        /// contains a wildcard, and `nil` when there is no vary. Otherwise the key is the
        /// SHA-256 hex digest of the normalized `name=value` pairs, so request header values
        /// (e.g. an `Authorization` token) are never stored in clear.
        /// - Parameters:
        ///   - varyHeader: The response `Vary` header value, or `nil` when absent.
        ///   - requestHeaders: The request headers whose values are selected by `Vary`.
        static func varyKey(for varyHeader: String?, requestHeaders: [String: String]?) -> String? {
            guard let varyHeader else { return nil }
            let names = Set(varyHeader
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty })
            guard !names.isEmpty else { return nil }
            if names.contains("*") { return "*" }

            var lowercasedHeaders: [String: String] = [:]
            for (key, value) in requestHeaders ?? [:] {
                lowercasedHeaders[key.lowercased()] = value
            }
            return names.sorted().map { "\($0)=\(lowercasedHeaders[$0] ?? "")" }.joined(separator: "\n").sha256Hex
        }

        // MARK: - Disk Operations

        /// Reads and decodes the entry for a key. Files in an unknown format or version are
        /// deleted and reported as a miss.
        private func loadDiskEntry(forKey key: String) async -> (HCache.EntryMetadata, Data)? {
            let dir = self.cacheDirectory
            let result: DiskRead = await withCheckedContinuation { continuation in
                diskQueue.async {
                    continuation.resume(returning: FileStorage.readEntry(at: FileStorage.url(for: key, in: dir)))
                }
            }
            switch result {
            case .missing:
                return nil
            case .invalid:
                await removeDiskData(forKey: key)
                return nil
            case .entry(let metadata, let body):
                return (metadata, body)
            }
        }

        /// Reads only the metadata header of the entry for a key.
        private func readDiskMetadata(forKey key: String) async -> HCache.EntryMetadata? {
            let dir = self.cacheDirectory
            return await withCheckedContinuation { continuation in
                diskQueue.async {
                    continuation.resume(returning: FileStorage.readMetadata(at: FileStorage.url(for: key, in: dir)))
                }
            }
        }

        private func removeDiskData(forKey key: String) async {
            let dir = self.cacheDirectory
            await withCheckedContinuation { continuation in
                diskQueue.async(flags: .barrier) {
                    let fileURL = FileStorage.url(for: key, in: dir)
                    try? FileManager.default.removeItem(at: fileURL)

                    // Cleanup legacy files if present
                    let legacyURLs = FileStorage.legacyUrls(for: key, in: dir)
                    try? FileManager.default.removeItem(at: legacyURLs.0)
                    try? FileManager.default.removeItem(at: legacyURLs.1)
                    continuation.resume()
                }
            }
            diskIndex?.remove(FileStorage.fileName(for: key))
            lastPersistedAccess[FileStorage.fileName(for: key)] = nil
        }

        /// Persists the entry on disk and, when the write succeeds, promotes it to memory and
        /// enforces the disk capacity. On failure the previous entry (if any) is left untouched
        /// in both levels.
        /// - Parameters:
        ///   - entry: The entry to persist.
        ///   - key: The cache key.
        ///   - diskCapacity: The disk capacity in bytes.
        ///   - token: The clear token observed before the entry was produced. When a
        ///     `clearAllCache` ran since, the entry is not promoted nor indexed.
        private func persist(_ entry: Entry, forKey key: String, diskCapacity: Int, token: Int) async {
            guard let fileData = try? DiskCodec.encode(entry.metadata, body: entry.data) else {
                HLogger.log("Failed to encode cache entry", level: .error)
                return
            }

            let written = await writeToDisk(fileData, forKey: key)

            // Prevent L1/L2 desync if a clearAllCache executed while we were suspended writing to disk.
            // The clear's barrier runs after this write, so the file itself is gone as well.
            guard token == cacheClearToken else { return }

            guard written else {
                HLogger.log("Failed to persist cache entry on disk", level: .error)
                return
            }

            memoryCache.setObject(entry, forKey: NSString(string: key), cost: entry.data.count)
            // The write itself set the file's modification date.
            recordPersistedAccess(FileStorage.fileName(for: key), at: Date())
            await recordDiskWrite(forKey: key, size: fileData.count, diskCapacity: diskCapacity, token: token)
        }

        /// Writes the encoded entry atomically. On iOS-family platforms the file is created with
        /// `completeUntilFirstUserAuthentication` protection, so it is never readable unprotected.
        /// Returns whether the write succeeded.
        private func writeToDisk(_ fileData: Data, forKey key: String) async -> Bool {
            let dir = self.cacheDirectory
            return await withCheckedContinuation { continuation in
                diskQueue.async(flags: .barrier) {
                    let fileURL = FileStorage.url(for: key, in: dir)
                    do {
                        try fileData.write(to: fileURL, options: FileStorage.writeOptions)

                        // Cleanup legacy files just in case they exist for this key
                        let legacyURLs = FileStorage.legacyUrls(for: key, in: dir)
                        try? FileManager.default.removeItem(at: legacyURLs.0)
                        try? FileManager.default.removeItem(at: legacyURLs.1)

                        continuation.resume(returning: true)
                    } catch {
                        // The write is atomic: on failure the previous file (if any) is intact.
                        continuation.resume(returning: false)
                    }
                }
            }
        }

        /// Records a written file in the disk index and evicts the least recently used files
        /// until the disk capacity is respected. The file just written is never evicted.
        private func recordDiskWrite(forKey key: String, size: Int, diskCapacity: Int, token: Int) async {
            await ensureDiskIndex()
            guard token == cacheClearToken, diskIndex != nil else { return }

            let name = FileStorage.fileName(for: key)
            diskIndex?.upsert(name, size: size, lastAccess: Date())

            let victims = diskIndex?.evictionCandidates(toFit: diskCapacity, excluding: name) ?? []
            guard !victims.isEmpty else { return }
            for victim in victims {
                diskIndex?.remove(victim)
            }

            let dir = self.cacheDirectory
            await withCheckedContinuation { continuation in
                diskQueue.async(flags: .barrier) {
                    for victim in victims {
                        try? FileManager.default.removeItem(at: dir.appendingPathComponent(victim))
                    }
                    continuation.resume()
                }
            }
        }

        /// Builds the disk index from a single directory listing (sizes and modification
        /// dates only, no file is read). Concurrent callers share one build.
        private func ensureDiskIndex() async {
            guard diskIndex == nil else { return }
            if let build = diskIndexBuild {
                await build.value
                return
            }

            let dir = self.cacheDirectory
            let queue = self.diskQueue
            let token = cacheClearToken
            let build = Task { @HRequestManagerActor in
                let built: DiskIndex = await withCheckedContinuation { continuation in
                    queue.async {
                        continuation.resume(returning: FileStorage.buildIndex(at: dir))
                    }
                }
                if self.diskIndex == nil {
                    self.diskIndex = token == self.cacheClearToken ? built : DiskIndex()
                }
                self.diskIndexBuild = nil
            }
            diskIndexBuild = build
            await build.value
        }

        /// Records a read of the entry for a key: refreshes its access time in the index, and on
        /// disk (the file's modification date, which seeds the index on the next launch) at most
        /// once per `accessTimePersistInterval` per entry. The throttle is tracked per key in
        /// memory, so it holds before the disk index exists and for pure memory hits.
        private func noteAccess(forKey key: String) {
            let name = FileStorage.fileName(for: key)
            let now = Date()
            diskIndex?.touch(name, at: now)
            if let last = lastPersistedAccess[name], now.timeIntervalSince(last) < Self.accessTimePersistInterval { return }
            recordPersistedAccess(name, at: now)

            diskAccessTouchCount += 1
            let fileURL = cacheDirectory.appendingPathComponent(name)
            diskQueue.async {
                try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: fileURL.path)
            }
        }

        /// Records that the access time of a file was persisted, pruning records that no longer
        /// throttle anything once the map grows past `maxPersistedAccessRecords`.
        private func recordPersistedAccess(_ name: String, at date: Date) {
            lastPersistedAccess[name] = date
            guard lastPersistedAccess.count > Self.maxPersistedAccessRecords else { return }
            lastPersistedAccess = lastPersistedAccess.filter { date.timeIntervalSince($0.value) < Self.accessTimePersistInterval }
            if lastPersistedAccess.count > Self.maxPersistedAccessRecords {
                lastPersistedAccess = [name: date]
            }
        }

        /// Discards expired entries without validators, files in an outdated format and legacy
        /// files. Only metadata headers are read, on a background-priority concurrent read so
        /// regular cache traffic is not blocked; deletions skip files modified since the scan.
        private func performStartupCleanup() async {
            let dir = self.cacheDirectory
            let token = cacheClearToken
            let candidates: [FileStorage.DiscardCandidate] = await withCheckedContinuation { continuation in
                diskQueue.async(qos: .background) {
                    continuation.resume(returning: FileStorage.discardCandidates(at: dir))
                }
            }
            guard !candidates.isEmpty, token == cacheClearToken else { return }

            let removed: [String] = await withCheckedContinuation { continuation in
                diskQueue.async(flags: .barrier) {
                    continuation.resume(returning: FileStorage.remove(candidates))
                }
            }
            for name in removed {
                diskIndex?.remove(name)
            }
        }
    }
}

// MARK: - Default Decoding

extension HCache.Manager {
    /// Retrieves cached data decoded with Harbor's shared `JSONDecoder` (see `getCachedData(forKey:config:requestHeaders:decode:)`).
    func getCachedData<T: HModel>(forKey key: String, type: T.Type, config: HCache.Configuration, requestHeaders: [String: String]? = nil) async -> T? {
        await getCachedData(forKey: key, config: config, requestHeaders: requestHeaders) { try HConfig.jsonDecoder.decode(T.self, from: $0) }
    }

    /// Retrieves a revalidatable body decoded with Harbor's shared `JSONDecoder` (see `getRevalidatableCachedData(forKey:requestHeaders:decode:)`).
    func getRevalidatableCachedData<T: HModel>(forKey key: String, type: T.Type, requestHeaders: [String: String]? = nil) async -> T? {
        await getRevalidatableCachedData(forKey: key, requestHeaders: requestHeaders) { try HConfig.jsonDecoder.decode(T.self, from: $0) }
    }

    /// Retrieves a `stale-if-error` body decoded with Harbor's shared `JSONDecoder` (see `getStaleOnErrorData(forKey:requestHeaders:decode:)`).
    func getStaleOnErrorData<T: HModel>(forKey key: String, type: T.Type, requestHeaders: [String: String]? = nil) async -> T? {
        await getStaleOnErrorData(forKey: key, requestHeaders: requestHeaders) { try HConfig.jsonDecoder.decode(T.self, from: $0) }
    }
}

// MARK: - Disk Format

extension HCache {
    /// On-disk entry format: the 4-byte magic `HRBC`, a 4-byte big-endian length, the JSON
    /// encoded `EntryMetadata` of that length, and the raw body bytes. The metadata can be
    /// read without loading the body; files without the magic or with another
    /// `EntryMetadata.version` are rejected.
    enum DiskCodec {
        /// File signature.
        static let magic = Data("HRBC".utf8)
        /// Bytes before the metadata header: the magic plus the header length.
        static let prefixLength = 8
        /// Upper bound for a metadata header, guarding against corrupted lengths.
        static let maxHeaderLength = 1024 * 1024

        /// Encodes an entry into its file representation.
        /// - Parameters:
        ///   - metadata: The entry metadata.
        ///   - body: The raw response body.
        /// - Returns: The file contents.
        static func encode(_ metadata: EntryMetadata, body: Data) throws -> Data {
            let header = try JSONEncoder().encode(metadata)
            var fileData = Data(capacity: prefixLength + header.count + body.count)
            fileData.append(magic)
            let length = UInt32(header.count)
            fileData.append(contentsOf: [UInt8(length >> 24 & 0xFF), UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)])
            fileData.append(header)
            fileData.append(body)
            return fileData
        }

        /// Decodes a whole file into its metadata and body, or `nil` when the format or version is unknown.
        /// - Parameter fileData: The file contents.
        static func decode(_ fileData: Data) -> (EntryMetadata, Data)? {
            guard let headerLength = headerLength(fromPrefix: fileData),
                  fileData.count >= prefixLength + headerLength else { return nil }
            let headerStart = fileData.startIndex + prefixLength
            let bodyStart = headerStart + headerLength
            guard let metadata = decodeMetadata(fileData.subdata(in: headerStart ..< bodyStart)) else { return nil }
            return (metadata, fileData.subdata(in: bodyStart ..< fileData.endIndex))
        }

        /// Reads the metadata length from the first `prefixLength` bytes of a file.
        /// - Parameter prefix: At least the first `prefixLength` bytes of the file.
        static func headerLength(fromPrefix prefix: Data) -> Int? {
            guard prefix.count >= prefixLength,
                  prefix.prefix(magic.count).elementsEqual(magic) else { return nil }
            let length = prefix.dropFirst(magic.count).prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            return length <= maxHeaderLength ? length : nil
        }

        /// Decodes a metadata header, rejecting other schema versions.
        /// - Parameter header: The JSON metadata header.
        static func decodeMetadata(_ header: Data) -> EntryMetadata? {
            guard let metadata = try? JSONDecoder().decode(EntryMetadata.self, from: header),
                  metadata.version == EntryMetadata.currentVersion else { return nil }
            return metadata
        }
    }

    /// Size and last access time of the files in the cache directory, keyed by file name.
    struct DiskIndex: Sendable {
        /// One indexed file.
        struct Record: Sendable {
            /// File size in bytes.
            var size: Int
            /// Last read or write.
            var lastAccess: Date
        }

        /// Indexed files keyed by file name.
        private(set) var records: [String: Record]
        /// Sum of the indexed file sizes.
        private(set) var totalSize: Int

        init(records: [String: Record] = [:]) {
            self.records = records
            self.totalSize = records.values.reduce(0) { $0 + $1.size }
        }

        /// Adds or replaces a file.
        mutating func upsert(_ name: String, size: Int, lastAccess: Date) {
            totalSize += size - (records[name]?.size ?? 0)
            records[name] = Record(size: size, lastAccess: lastAccess)
        }

        /// Removes a file.
        mutating func remove(_ name: String) {
            if let record = records.removeValue(forKey: name) {
                totalSize -= record.size
            }
        }

        /// Refreshes the access time of a file and returns the previous one, or `nil` when the
        /// file is not indexed.
        @discardableResult
        mutating func touch(_ name: String, at date: Date) -> Date? {
            guard var record = records[name] else { return nil }
            let previous = record.lastAccess
            record.lastAccess = date
            records[name] = record
            return previous
        }

        /// The least recently used files to remove so the total fits `maxBytes`, oldest first.
        /// - Parameters:
        ///   - maxBytes: The capacity to fit.
        ///   - excludedName: A file that is never selected.
        func evictionCandidates(toFit maxBytes: Int, excluding excludedName: String?) -> [String] {
            guard totalSize > maxBytes else { return [] }
            var excess = totalSize - maxBytes
            var victims: [String] = []
            let ordered = records
                .filter { $0.key != excludedName }
                .sorted { ($0.value.lastAccess, $0.key) < ($1.value.lastAccess, $1.key) }
            for (name, record) in ordered {
                guard excess > 0 else { break }
                victims.append(name)
                excess -= record.size
            }
            return victims
        }
    }
}

// MARK: - Private File Storage Implementation

private extension HCache {
    /// Result of reading an entry file.
    enum DiskRead: Sendable {
        case missing
        case invalid
        case entry(EntryMetadata, Data)
    }

    /// Encapsulates low-level file system operations to avoid actor isolation conflicts.
    /// Being a separate struct, it does not inherit @HRequestManagerActor isolation.
    struct FileStorage {
        /// A file the startup cleanup may delete, with the modification date seen by the scan.
        struct DiscardCandidate: Sendable {
            let url: URL
            let modificationDate: Date?
        }

        /// Options for entry writes: atomic, and protected until first unlock on iOS-family platforms.
        static var writeOptions: Data.WritingOptions {
            #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            return [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            #else
            return [.atomic]
            #endif
        }

        /// File name of the entry for a key.
        /// - Parameter key: The cache key string.
        static func fileName(for key: String) -> String {
            // Using .cache extension to distinguish from legacy files
            return "\(key.sha256Hex).cache"
        }

        /// Generates the file URL for a cache entry based on its key hash.
        /// - Parameters:
        ///   - key: The cache key string.
        ///   - directory: The cache directory holding the entry files.
        static func url(for key: String, in directory: URL) -> URL {
            return directory.appendingPathComponent(fileName(for: key))
        }

        /// Generates URLs for legacy cache formats (data and metadata files).
        /// - Parameters:
        ///   - key: The cache key string.
        ///   - directory: The cache directory holding the entry files.
        static func legacyUrls(for key: String, in directory: URL) -> (URL, URL) {
            let hash = key.sha256Hex
            let dataURL = directory.appendingPathComponent(hash)
            let metaURL = dataURL.appendingPathExtension("meta")
            return (dataURL, metaURL)
        }

        /// Reads and decodes a whole entry file.
        /// - Parameter fileURL: The file URL.
        static func readEntry(at fileURL: URL) -> DiskRead {
            guard let fileData = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return .missing }
            guard let (metadata, body) = DiskCodec.decode(fileData) else { return .invalid }
            return .entry(metadata, body)
        }

        /// Reads only the metadata header of an entry file.
        /// - Parameter fileURL: The file URL.
        static func readMetadata(at fileURL: URL) -> EntryMetadata? {
            guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
            defer { try? handle.close() }
            guard let prefix = try? handle.read(upToCount: DiskCodec.prefixLength),
                  let headerLength = DiskCodec.headerLength(fromPrefix: prefix),
                  let header = try? handle.read(upToCount: headerLength),
                  header.count == headerLength else { return nil }
            return DiskCodec.decodeMetadata(header)
        }

        /// Builds the disk index from the directory listing: sizes and modification dates only.
        /// - Parameter directory: The cache directory to list.
        static func buildIndex(at directory: URL) -> DiskIndex {
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return DiskIndex() }

            var records: [String: DiskIndex.Record] = [:]
            for fileURL in files where fileURL.pathExtension == "cache" {
                let values = try? fileURL.resourceValues(forKeys: Set(keys))
                records[fileURL.lastPathComponent] = DiskIndex.Record(size: values?.fileSize ?? 0, lastAccess: values?.contentModificationDate ?? .distantPast)
            }
            return DiskIndex(records: records)
        }

        /// Lists the files the startup cleanup should delete: expired entries without
        /// validators (past any `stale-while-revalidate` window), unreadable or outdated
        /// entries, and legacy files.
        /// - Parameter directory: The cache directory to scan.
        static func discardCandidates(at directory: URL) -> [DiscardCandidate] {
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }

            var candidates: [DiscardCandidate] = []
            for fileURL in files {
                switch fileURL.pathExtension {
                case "cache":
                    let modificationDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    guard let metadata = readMetadata(at: fileURL) else {
                        candidates.append(DiscardCandidate(url: fileURL, modificationDate: modificationDate))
                        continue
                    }
                    // Entries with validators are kept even when expired: they can still be revalidated.
                    if !metadata.hasValidator, metadata.isExpired(maxAge: nil, grace: metadata.servableStaleWindow) {
                        candidates.append(DiscardCandidate(url: fileURL, modificationDate: modificationDate))
                    }
                case "meta":
                    // Legacy format: data file plus a .meta sidecar.
                    candidates.append(DiscardCandidate(url: fileURL, modificationDate: nil))
                    candidates.append(DiscardCandidate(url: fileURL.deletingPathExtension(), modificationDate: nil))
                default:
                    continue
                }
            }
            return candidates
        }

        /// Deletes the candidates that were not modified since they were scanned.
        /// - Parameter candidates: The files to delete.
        /// - Returns: The names of the deleted files.
        static func remove(_ candidates: [DiscardCandidate]) -> [String] {
            var removed: [String] = []
            for candidate in candidates {
                if let scanned = candidate.modificationDate {
                    let current = (try? candidate.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    guard current == scanned else { continue }
                }
                if (try? FileManager.default.removeItem(at: candidate.url)) != nil {
                    removed.append(candidate.url.lastPathComponent)
                }
            }
            return removed
        }
    }
}

// MARK: - Supporting Types

/// Recognized `Cache-Control` directives. `public`/`private` are parsed for completeness;
/// they do not change behavior because Harbor's custom cache is a private cache.
struct CacheControlDirectives {
    /// The maximum age in seconds specified by `max-age`.
    var maxAge: Int?
    /// The maximum age in seconds specified by `s-maxage`.
    var sMaxAge: Int?
    /// Whether `no-cache` is specified.
    var noCache = false
    /// Whether `no-store` is specified.
    var noStore = false
    /// Whether `must-revalidate` is specified.
    var mustRevalidate = false
    /// Whether `proxy-revalidate` is specified.
    var proxyRevalidate = false
    /// The window in seconds for `stale-while-revalidate`.
    var staleWhileRevalidate: Int?
    /// The window in seconds for `stale-if-error`.
    var staleIfError: Int?
    /// Whether `public` is specified.
    var isPublic = false
    /// Whether `private` is specified.
    var isPrivate = false
}
