//
//  HCache+Manager.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import Foundation

public enum HCache {}

extension HCache {
    /// Two-level (memory + disk) cache manager with granular expiration control and
    /// HTTP revalidation support (ETag / Last-Modified).
    ///
    /// Marked `@unchecked Sendable`: memory access is serialized by `@HRequestManagerActor`,
    /// disk access by `diskQueue` (writes and deletes run under a barrier), and `NSCache`
    /// is internally thread-safe.
    @HRequestManagerActor
    final class Manager: @unchecked Sendable {

        /// Shared instance of the cache manager.
        static let shared = Manager()

        /// Fast in-memory cache (L1)
        private let memoryCache = NSCache<NSString, Entry>()

        /// Cache directory for persistence (L2)
        let cacheDirectory: URL

        /// Concurrent queue for disk I/O. Reads run concurrently; writes and deletes run under a barrier.
        private let diskQueue = DispatchQueue(label: "harbor.cache.disk", qos: .utility, attributes: .concurrent)

        /// Shared coders. Access is serialized by the actor.
        private static let jsonDecoder = JSONDecoder()
        private static let jsonEncoder = JSONEncoder()

        private init() {
            // 1. Setup cache directory safely in Library/Caches
            guard let systemCacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                self.cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("HarborCache")
                return
            }

            self.cacheDirectory = systemCacheDir.appendingPathComponent("HarborCache", isDirectory: true)

            // 2. Create directory
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

            // 3. Configure NSCache limits
            memoryCache.totalCostLimit = Configuration().memoryCacheCapacityInBytes
            memoryCache.countLimit = 500

            // 4. Perform background cleanup
            let dir = self.cacheDirectory
            Task.detached(priority: .background) {
                FileStorage.cleanupExpiredFiles(at: dir)
            }
        }

        // MARK: - Public API

        /// Retrieves cached data by key (for custom cache type).
        ///
        /// Expired entries are never served. Entries that carry validators (ETag / Last-Modified)
        /// or that must always be revalidated (`Cache-Control: no-cache`) are kept as a source of
        /// validators instead of being deleted; entries without validators are evicted on expiration.
        func getCachedData<T: HModel>(forKey key: String, type: T.Type, config: HCache.Configuration, requestHeaders: [String: String]? = nil) async -> T? {
            let nsKey = NSString(string: key)

            // L1: Memory Cache
            if let entry = memoryCache.object(forKey: nsKey) {
                if entry.isExpired(maxAge: config.expirationTime) {
                    if !entry.hasValidator { memoryCache.removeObject(forKey: nsKey) }
                    return nil
                }
                guard entry.matchesVary(Self.varyKey(for: entry.vary, requestHeaders: requestHeaders)) else { return nil }
                return try? Self.jsonDecoder.decode(type, from: entry.data)
            }

            // L2: Disk Cache
            guard let fileData = await readDiskData(forKey: key),
                  let diskEntry = try? Self.jsonDecoder.decode(DiskEntry.self, from: fileData),
                  diskEntry.version == DiskEntry.currentVersion else {
                return nil
            }

            // Vary mismatch: the stored variant cannot satisfy this request.
            guard diskEntry.matchesVary(Self.varyKey(for: diskEntry.vary, requestHeaders: requestHeaders)) else {
                await removeDiskData(forKey: key)
                return nil
            }

            // Expiration: keep entries that can still be revalidated, evict the rest.
            if diskEntry.isExpired(maxAge: config.expirationTime) {
                if !diskEntry.hasValidator {
                    await removeDiskData(forKey: key)
                }
                return nil
            }

            guard let model = try? Self.jsonDecoder.decode(type, from: diskEntry.data) else { return nil }

            // Promote to Memory Cache
            memoryCache.setObject(diskEntry.toEntry(), forKey: nsKey, cost: diskEntry.data.count)

            return model
        }

        /// Returns the cached body for a key even when the entry is expired, as long as it carries a
        /// validator (ETag / Last-Modified). Used to satisfy a `304 Not Modified` revalidation.
        func getRevalidatableCachedData<T: HModel>(forKey key: String, type: T.Type, requestHeaders: [String: String]? = nil) async -> T? {
            let nsKey = NSString(string: key)

            if let entry = memoryCache.object(forKey: nsKey) {
                guard entry.hasValidator, entry.matchesVaryOrWildcard(Self.varyKey(for: entry.vary, requestHeaders: requestHeaders)) else { return nil }
                return try? Self.jsonDecoder.decode(type, from: entry.data)
            }

            guard let fileData = await readDiskData(forKey: key),
                  let diskEntry = try? Self.jsonDecoder.decode(DiskEntry.self, from: fileData),
                  diskEntry.version == DiskEntry.currentVersion,
                  diskEntry.hasValidator,
                  diskEntry.matchesVaryOrWildcard(Self.varyKey(for: diskEntry.vary, requestHeaders: requestHeaders)) else {
                return nil
            }

            return try? Self.jsonDecoder.decode(type, from: diskEntry.data)
        }

        /// Returns an expired entry when its `stale-if-error` window still allows serving it.
        /// Entries marked `must-revalidate` are never served stale.
        func getStaleOnErrorData<T: HModel>(forKey key: String, type: T.Type, requestHeaders: [String: String]? = nil) async -> T? {
            func staleModel<E: HCacheEntryInfo & HCacheStaleServing>(from entry: E, data: Data) -> T? {
                guard !entry.mustRevalidate,
                      entry.isExpired(maxAge: nil),
                      let window = entry.staleIfError,
                      let freshness = entry.expirationTime,
                      Date().timeIntervalSince(entry.timestamp) - freshness <= window,
                      entry.matchesVary(Self.varyKey(for: entry.vary, requestHeaders: requestHeaders)) else { return nil }
                return try? Self.jsonDecoder.decode(type, from: data)
            }

            if let entry = memoryCache.object(forKey: NSString(string: key)) {
                return staleModel(from: entry, data: entry.data)
            }

            guard let fileData = await readDiskData(forKey: key),
                  let diskEntry = try? Self.jsonDecoder.decode(DiskEntry.self, from: fileData),
                  diskEntry.version == DiskEntry.currentVersion else {
                return nil
            }
            return staleModel(from: diskEntry, data: diskEntry.data)
        }

        /// Stores data by key (for custom cache type), honoring the response cache directives.
        ///
        /// - `no-store` responses are not persisted at all.
        /// - `no-cache` responses are persisted but marked always stale, so they are never
        ///   served without revalidation while their validators are preserved.
        /// - `Vary` is stored and enforced on reads; `Vary: *` entries are never served directly.
        func storeData(_ data: Data, forKey key: String, config: HCache.Configuration, response: HTTPURLResponse?, requestHeaders: [String: String]? = nil) async {
            guard data.count <= config.maxObjectSizeInBytes else { return }

            let directives = response?.value(forHTTPHeaderField: "Cache-Control").map { Self.parseCacheControlDirectives($0) }

            // no-store: the response must not be persisted.
            if directives?.noStore == true { return }

            let vary = response?.value(forHTTPHeaderField: "Vary")
            let varyKey = Self.varyKey(for: vary, requestHeaders: requestHeaders)

            let entry = Entry(
                data: data,
                timestamp: Date(),
                expirationTime: calculateEffectiveExpirationTime(fromResponse: response, fallbackTime: config.expirationTime),
                etag: response?.value(forHTTPHeaderField: "ETag"),
                lastModified: response?.value(forHTTPHeaderField: "Last-Modified"),
                vary: vary,
                varyKey: varyKey,
                alwaysStale: directives?.noCache == true || varyKey == "*",
                mustRevalidate: directives?.mustRevalidate == true || directives?.proxyRevalidate == true,
                staleIfError: directives?.staleIfError.map { TimeInterval($0) }
            )

            // Apply the memory capacity from the effective configuration before inserting.
            memoryCache.totalCostLimit = config.memoryCacheCapacityInBytes

            // Persist to disk first; only promote to memory when the write succeeds.
            let written = await writeToDisk(DiskEntry(entry: entry), forKey: key, diskCapacity: config.diskCacheCapacityInBytes)
            if written {
                memoryCache.setObject(entry, forKey: NSString(string: key), cost: data.count)
            } else {
                memoryCache.removeObject(forKey: NSString(string: key))
                HarborLogger.log("Failed to persist cache entry on disk", level: .error)
            }
        }

        /// Refreshes the stored entry after a `304 Not Modified`: updates the timestamp and the
        /// expiration from the response headers, and merges any updated validators.
        func refreshEntry(forKey key: String, response: HTTPURLResponse?, config: HCache.Configuration) async {
            let nsKey = NSString(string: key)

            var entry = memoryCache.object(forKey: nsKey)
            if entry == nil,
               let fileData = await readDiskData(forKey: key),
               let diskEntry = try? Self.jsonDecoder.decode(DiskEntry.self, from: fileData),
               diskEntry.version == DiskEntry.currentVersion {
                entry = diskEntry.toEntry()
            }

            guard let entry else { return }

            let directives = response?.value(forHTTPHeaderField: "Cache-Control").map { Self.parseCacheControlDirectives($0) }

            let refreshed = Entry(
                data: entry.data,
                timestamp: Date(),
                expirationTime: calculateEffectiveExpirationTime(fromResponse: response, fallbackTime: config.expirationTime),
                etag: response?.value(forHTTPHeaderField: "ETag") ?? entry.etag,
                lastModified: response?.value(forHTTPHeaderField: "Last-Modified") ?? entry.lastModified,
                vary: entry.vary,
                varyKey: entry.varyKey,
                alwaysStale: directives?.noCache ?? entry.alwaysStale,
                mustRevalidate: directives.map { $0.mustRevalidate || $0.proxyRevalidate } ?? entry.mustRevalidate,
                staleIfError: directives?.staleIfError.map { TimeInterval($0) } ?? entry.staleIfError
            )

            memoryCache.setObject(refreshed, forKey: nsKey, cost: refreshed.data.count)
            _ = await writeToDisk(DiskEntry(entry: refreshed), forKey: key, diskCapacity: config.diskCacheCapacityInBytes)
        }

        /// Returns the stored validators (ETag and Last-Modified) for the given cache key, if available.
        /// Entries whose `Vary` does not match the request headers are ignored.
        func getValidators(forKey key: String, requestHeaders: [String: String]? = nil) async -> (etag: String?, lastModified: String?) {
            if let entry = memoryCache.object(forKey: NSString(string: key)) {
                guard entry.matchesVaryOrWildcard(Self.varyKey(for: entry.vary, requestHeaders: requestHeaders)) else { return (nil, nil) }
                return (entry.etag, entry.lastModified)
            }

            guard let fileData = await readDiskData(forKey: key),
                  let diskEntry = try? Self.jsonDecoder.decode(DiskEntry.self, from: fileData),
                  diskEntry.version == DiskEntry.currentVersion,
                  diskEntry.matchesVaryOrWildcard(Self.varyKey(for: diskEntry.vary, requestHeaders: requestHeaders)) else {
                return (nil, nil)
            }
            return (diskEntry.etag, diskEntry.lastModified)
        }

        /// Returns the stored ETag for the given cache key, if available.
        func getETag(forKey key: String) async -> String? {
            if let entry = memoryCache.object(forKey: NSString(string: key)) {
                return entry.etag
            }

            guard let fileData = await readDiskData(forKey: key),
                  let diskEntry = try? Self.jsonDecoder.decode(DiskEntry.self, from: fileData),
                  diskEntry.version == DiskEntry.currentVersion else {
                return nil
            }
            return diskEntry.etag
        }

        /// Clears all cached data, waiting until disk cleanup completes.
        func clearAllCache() async {
            memoryCache.removeAllObjects()

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
        func removeCachedData(for key: String) async {
            memoryCache.removeObject(forKey: NSString(string: key))
            await removeDiskData(forKey: key)
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

        // MARK: - Expiration Logic

        /// Resolves the effective expiration time honoring the response cache directives
        /// (`s-maxage` and `max-age` take precedence over `Expires`, which takes precedence
        /// over the configured fallback).
        func calculateEffectiveExpirationTime(fromResponse response: HTTPURLResponse?, fallbackTime: TimeInterval?) -> TimeInterval? {
            guard let response = response else { return fallbackTime }

            if let cacheControl = response.value(forHTTPHeaderField: "Cache-Control") {
                let directives = Self.parseCacheControlDirectives(cacheControl)
                if let sMaxAge = directives.sMaxAge { return TimeInterval(sMaxAge) }
                if let maxAge = directives.maxAge { return TimeInterval(maxAge) }
            }

            if let expiresString = response.value(forHTTPHeaderField: "Expires"),
               let expiresDate = Self.parseHTTPDate(expiresString) {
                return max(expiresDate.timeIntervalSinceNow, 0)
            }

            return fallbackTime
        }

        /// Parses a `Cache-Control` header into its directives. Header parsing is case-insensitive
        /// and unknown or malformed directives are ignored.
        static func parseCacheControlDirectives(_ cacheControl: String) -> CacheControlDirectives {
            let directives = cacheControl.lowercased().components(separatedBy: ",")
            var result = CacheControlDirectives()

            for directive in directives {
                let trimmed = directive.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("s-maxage=") {
                    result.sMaxAge = Int(String(trimmed.dropFirst(9)))
                } else if trimmed.hasPrefix("max-age=") {
                    result.maxAge = Int(String(trimmed.dropFirst(8)))
                } else if trimmed.hasPrefix("stale-while-revalidate=") {
                    result.staleWhileRevalidate = Int(String(trimmed.dropFirst(23)))
                } else if trimmed.hasPrefix("stale-if-error=") {
                    result.staleIfError = Int(String(trimmed.dropFirst(15)))
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
        static func parseHTTPDate(_ string: String) -> Date? {
            for formatter in httpDateFormatters {
                if let date = formatter.date(from: string) { return date }
            }
            return nil
        }

        /// Resolves the values of the header fields listed in a `Vary` header from the given
        /// request headers, producing a comparable key. Returns `"*"` when the vary header
        /// contains a wildcard, and `nil` when there is no vary.
        static func varyKey(for varyHeader: String?, requestHeaders: [String: String]?) -> String? {
            guard let varyHeader else { return nil }
            let names = varyHeader
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            guard !names.isEmpty else { return nil }
            if names.contains("*") { return "*" }

            var lowercasedHeaders: [String: String] = [:]
            for (key, value) in requestHeaders ?? [:] {
                lowercasedHeaders[key.lowercased()] = value
            }
            return names.sorted().map { "\($0)=\(lowercasedHeaders[$0] ?? "")" }.joined(separator: "\n")
        }

        // MARK: - Disk Operations

        private func readDiskData(forKey key: String) async -> Data? {
            let dir = self.cacheDirectory
            return await withCheckedContinuation { continuation in
                diskQueue.async {
                    let fileURL = FileStorage.url(for: key, in: dir)
                    continuation.resume(returning: try? Data(contentsOf: fileURL))
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
        }

        /// Persists the entry atomically and enforces the disk capacity afterwards.
        /// Returns whether the write succeeded.
        private func writeToDisk(_ diskEntry: DiskEntry, forKey key: String, diskCapacity: Int) async -> Bool {
            guard let encodedEntry = try? Self.jsonEncoder.encode(diskEntry) else { return false }

            let dir = self.cacheDirectory
            return await withCheckedContinuation { continuation in
                diskQueue.async(flags: .barrier) {
                    let fileURL = FileStorage.url(for: key, in: dir)
                    do {
                        try encodedEntry.write(to: fileURL, options: .atomic)
                        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
                        #endif

                        // Cleanup legacy files just in case they exist for this key
                        let legacyURLs = FileStorage.legacyUrls(for: key, in: dir)
                        try? FileManager.default.removeItem(at: legacyURLs.0)
                        try? FileManager.default.removeItem(at: legacyURLs.1)

                        FileStorage.enforceCapacity(at: dir, maxBytes: diskCapacity)

                        continuation.resume(returning: true)
                    } catch {
                        try? FileManager.default.removeItem(at: fileURL)
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }
}

// MARK: - Private File Storage Implementation

private extension HCache {
    /// Encapsulates low-level file system operations to avoid actor isolation conflicts.
    /// Being a separate struct, it does not inherit @HRequestManagerActor isolation.
    struct FileStorage {
        static func url(for key: String, in directory: URL) -> URL {
            let hash = key.sha256Hash
            // Using .cache extension to distinguish from legacy files
            return directory.appendingPathComponent(hash).appendingPathExtension("cache")
        }

        static func legacyUrls(for key: String, in directory: URL) -> (URL, URL) {
            let hash = key.sha256Hash
            let dataURL = directory.appendingPathComponent(hash)
            let metaURL = dataURL.appendingPathExtension("meta")
            return (dataURL, metaURL)
        }

        static func cleanupExpiredFiles(at directory: URL) {
            guard let resourceKeys = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }

            // 1. Cleanup current format (.cache)
            let cacheFiles = resourceKeys.filter { $0.pathExtension == "cache" }
            for fileURL in cacheFiles {
                guard let data = try? Data(contentsOf: fileURL),
                      let diskEntry = try? JSONDecoder().decode(DiskEntry.self, from: data) else {
                    // Corrupted file? Remove it
                    try? FileManager.default.removeItem(at: fileURL)
                    continue
                }

                if diskEntry.version != DiskEntry.currentVersion {
                    try? FileManager.default.removeItem(at: fileURL)
                    continue
                }

                // Entries with validators are kept even when expired: they can still be revalidated.
                if diskEntry.isExpired(maxAge: nil), !diskEntry.hasValidator {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }

            // 2. Cleanup legacy format (.meta)
            let metaFiles = resourceKeys.filter { $0.pathExtension == "meta" }
            for metaURL in metaFiles {
                let dataURL = metaURL.deletingPathExtension()
                try? FileManager.default.removeItem(at: metaURL)
                try? FileManager.default.removeItem(at: dataURL)
            }
        }

        /// Evicts the oldest entries (by modification date) until the directory size fits the limit.
        static func enforceCapacity(at directory: URL, maxBytes: Int) {
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }

            var totalSize = 0
            var entries: [(url: URL, modificationDate: Date, size: Int)] = []

            for fileURL in files where fileURL.pathExtension == "cache" {
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let size = values?.fileSize ?? 0
                totalSize += size
                entries.append((fileURL, values?.contentModificationDate ?? .distantPast, size))
            }

            guard totalSize > maxBytes else { return }

            for entry in entries.sorted(by: { $0.modificationDate < $1.modificationDate }) {
                guard totalSize > maxBytes else { break }
                try? FileManager.default.removeItem(at: entry.url)
                totalSize -= entry.size
            }
        }
    }
}

// MARK: - Supporting Types

/// Recognized `Cache-Control` directives. `public`/`private` are parsed for completeness;
/// they do not change behavior because Harbor's custom cache is a private cache.
struct CacheControlDirectives {
    var maxAge: Int?
    var sMaxAge: Int?
    var noCache = false
    var noStore = false
    var mustRevalidate = false
    var proxyRevalidate = false
    var staleWhileRevalidate: Int?
    var staleIfError: Int?
    var isPublic = false
    var isPrivate = false
}

/// Metadata required to decide whether an expired entry may be served on errors.
private protocol HCacheStaleServing {
    var mustRevalidate: Bool { get }
    var staleIfError: TimeInterval? { get }
    var vary: String? { get }
    func matchesVary(_ currentVaryKey: String?) -> Bool
}

extension HCache.Manager.Entry: HCacheStaleServing {}

/// Disk persistence wrapper containing both data and metadata in a single file.
private struct DiskEntry: Codable, HCacheEntryInfo, HCacheStaleServing {
    /// Schema version of the current on-disk format.
    static let currentVersion = 1

    let version: Int
    let data: Data
    let timestamp: Date
    let expirationTime: TimeInterval?
    /// ETag header value stored for future If-None-Match requests.
    let etag: String?
    /// Last-Modified header value stored for future If-Modified-Since requests.
    let lastModified: String?
    let vary: String?
    let varyKey: String?
    let alwaysStale: Bool
    let mustRevalidate: Bool
    let staleIfError: TimeInterval?

    init(entry: HCache.Manager.Entry) {
        self.version = Self.currentVersion
        self.data = entry.data
        self.timestamp = entry.timestamp
        self.expirationTime = entry.expirationTime
        self.etag = entry.etag
        self.lastModified = entry.lastModified
        self.vary = entry.vary
        self.varyKey = entry.varyKey
        self.alwaysStale = entry.alwaysStale
        self.mustRevalidate = entry.mustRevalidate
        self.staleIfError = entry.staleIfError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Entries written before versioning was introduced are treated as version 1.
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.data = try container.decode(Data.self, forKey: .data)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.expirationTime = try container.decodeIfPresent(TimeInterval.self, forKey: .expirationTime)
        self.etag = try container.decodeIfPresent(String.self, forKey: .etag)
        self.lastModified = try container.decodeIfPresent(String.self, forKey: .lastModified)
        self.vary = try container.decodeIfPresent(String.self, forKey: .vary)
        self.varyKey = try container.decodeIfPresent(String.self, forKey: .varyKey)
        self.alwaysStale = try container.decodeIfPresent(Bool.self, forKey: .alwaysStale) ?? false
        self.mustRevalidate = try container.decodeIfPresent(Bool.self, forKey: .mustRevalidate) ?? false
        self.staleIfError = try container.decodeIfPresent(TimeInterval.self, forKey: .staleIfError)
    }

    var hasValidator: Bool {
        return etag != nil || lastModified != nil
    }

    func matchesVary(_ currentVaryKey: String?) -> Bool {
        if varyKey == "*" { return false }
        return varyKey == currentVaryKey
    }

    /// Vary check used for revalidation: `Vary: *` entries cannot be served directly,
    /// but their validators can still be used in conditional requests.
    func matchesVaryOrWildcard(_ currentVaryKey: String?) -> Bool {
        if varyKey == "*" { return true }
        return varyKey == currentVaryKey
    }

    func toEntry() -> HCache.Manager.Entry {
        return HCache.Manager.Entry(
            data: data,
            timestamp: timestamp,
            expirationTime: expirationTime,
            etag: etag,
            lastModified: lastModified,
            vary: vary,
            varyKey: varyKey,
            alwaysStale: alwaysStale,
            mustRevalidate: mustRevalidate,
            staleIfError: staleIfError
        )
    }
}
