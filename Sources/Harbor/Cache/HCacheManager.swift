//
//  HCacheManager.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import Foundation

public enum HCache {}

extension HCache {
    /// Pure NSCache-based cache manager with file system persistence.
    /// Eliminates URLCache overhead and duplication for maximum performance.
    @HRequestManagerActor
    final class Manager: Sendable {

        /// Shared instance of the cache manager.
        static let shared = Manager()
        
        /// Binary separator for metadata/data separation in cache files
        private let dataSeparator = Data([0xFF, 0xFF, 0xFF, 0xFF])

        /// Fast in-memory cache
        private let memoryCache = NSCache<NSString, Entry>()

        /// Cache directory for persistence
        private let cacheDirectory: URL

        /// Background queue for disk operations
        private let diskQueue = DispatchQueue(label: "harbor.cache.disk", qos: .utility)

        /// Cache for frequently accessed keys to avoid SHA256 recomputation
        private var keyCache = [String: String]()

        private init() {
            // Setup cache directory with proper error handling
            guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                // Fallback to temporary directory if cache directory is unavailable
                let fallbackDir = FileManager.default.temporaryDirectory
                self.cacheDirectory = fallbackDir.appendingPathComponent("Harbor")
                self.keyCache.reserveCapacity(1000)
                try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                return
            }
            self.cacheDirectory = cacheDir.appendingPathComponent("Harbor")

            // Initialize key cache with capacity for performance optimization
            self.keyCache.reserveCapacity(1000)

            // Create directory if needed
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

            // Configure NSCache
            let memoryMB = HRequestManager.config.defaultMemoryCacheCapacity
            memoryCache.totalCostLimit = memoryMB * 1024 * 1024
            memoryCache.countLimit = 1000
            memoryCache.evictsObjectsWithDiscardedContent = true

            // Load cached entries into memory for immediate availability
            loadAllCachedEntriesIntoMemory(capacity: HRequestManager.config.defaultStartUpMemoryCacheCapacity)
        }

        // MARK: - Public API

        /// Retrieves cached data for a request with result protocol.
        /// - Parameter request: The request object with associated model type.
        /// - Returns: The decoded model if found and valid, `nil` otherwise.
        func getCachedData<Request: HGetRequestProtocol>(for request: Request) async -> Request.Model? {
            let config = request.cacheConfiguration ?? HRequestManager.config.defaultCacheConfiguration
            guard config.isEnabled, let key = request.cacheKey else { return nil }

            return await getCachedData(for: key, type: Request.Model.self, maxAge: config.expirationTime)
        }

        /// Stores data for a request if caching is enabled.
        /// - Parameters:
        ///   - data: The response data to cache.
        ///   - request: The HGetRequestProtocol request object.
        ///   - response: The HTTP URL response for extracting cache headers.
        func storeData(_ data: Data, for request: any HGetRequestProtocol, response: HTTPURLResponse?) async {
            let config = request.cacheConfiguration ?? HRequestManager.config.defaultCacheConfiguration
            guard config.isEnabled, let key = request.cacheKey else { return }

            // Calculate effective expiration time prioritizing HTTP headers
            let effectiveExpirationTime = calculateEffectiveExpirationTime(
                fromResponse: response,
                fallbackTime: config.expirationTime
            )

            await storeData(data, for: key, expirationTime: effectiveExpirationTime)
        }

        /// Clears all cached data from both memory and disk.
        func clearAllCache() {
            memoryCache.removeAllObjects()
            keyCache.removeAll(keepingCapacity: true)

            diskQueue.async {
                try? FileManager.default.removeItem(at: self.cacheDirectory)
                try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
            }
        }

        /// Removes cached data for a specific key from both memory and disk.
        /// - Parameter key: The cache key to remove.
        func removeCachedData(for key: String) {
            let nsKey = NSString(string: key)
            memoryCache.removeObject(forKey: nsKey)
            keyCache.removeValue(forKey: key)

            diskQueue.async {
                let fileURL = self.fileURL(for: key)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}

// MARK: - Internal Implementation

private extension HCache.Manager {

    /// Loads cached entries from disk into memory asynchronously for immediate availability.
    /// Prioritizes most recently used entries and limits memory usage.
    func loadAllCachedEntriesIntoMemory(capacity: Int) {
        diskQueue.async {
            guard let files = try? FileManager.default.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                return
            }

            var totalMemoryUsed = 0
            let maxMemoryUsage = capacity * 1024 * 1024

            // Sort by modification date (most recent first) for better cache hit rates
            let sortedFiles = files
                .compactMap { url -> (URL, Date, Int)? in
                    guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                          let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
                    return (url, date, size)
                }
                .sorted { $0.1 > $1.1 } // Most recent first

            for (fileURL, _, _) in sortedFiles {
                guard totalMemoryUsed < maxMemoryUsage else { break }

                if let entry = self.loadEntryFromDisk(at: fileURL) {
                    // Check if expired and remove if so
                    if entry.isExpired(maxAge: entry.expirationTime) {
                        try? FileManager.default.removeItem(at: fileURL)
                        continue
                    }

                    // Load valid entry into memory cache on main actor
                    let key = fileURL.lastPathComponent
                    totalMemoryUsed += entry.data.count

                    Task { @HRequestManagerActor in
                        let nsKey = NSString(string: key)
                        self.memoryCache.setObject(entry, forKey: nsKey, cost: entry.data.count)
                    }
                }
            }
        }
    }

    // MARK: - Core Implementation

    func getCachedData<T: HModel>(for key: String, type: T.Type, maxAge: TimeInterval?) async -> T? {
        let nsKey = NSString(string: key)

        // 🚀 L1: Check memory cache first (fastest path)
        if let entry = memoryCache.object(forKey: nsKey) {
            if !entry.isExpired(maxAge: maxAge) {
                // Decode directly from memory - no async needed
                do {
                    return try JSONDecoder().decode(type, from: entry.data)
                } catch {
                    // Corrupted data - remove from memory only
                    memoryCache.removeObject(forKey: nsKey)
                }
            } else {
                // Expired - remove from memory
                memoryCache.removeObject(forKey: nsKey)
            }
        }

        // 💾 L2: Check disk cache
        return await withCheckedContinuation { continuation in
            diskQueue.async {
                let fileURL = self.fileURL(for: key)

                guard let entry = self.loadEntryFromDisk(at: fileURL),
                      !entry.isExpired(maxAge: maxAge) else {
                    // Remove expired file
                    try? FileManager.default.removeItem(at: fileURL)
                    continuation.resume(returning: nil)
                    return
                }

                // Try decode from disk
                do {
                    let model = try JSONDecoder().decode(type, from: entry.data)

                    // 📈 Promote to memory cache for faster future access
                    Task { @HRequestManagerActor in
                        let nsKey = NSString(string: key)
                        self.memoryCache.setObject(entry, forKey: nsKey, cost: entry.data.count)
                    }

                    continuation.resume(returning: model)
                } catch {
                    // Corrupted data - remove file
                    try? FileManager.default.removeItem(at: fileURL)
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func storeData(_ data: Data, for key: String, expirationTime: TimeInterval?) async {
        // Skip caching if data exceeds size limit
        guard data.count < 4 * 1024 * 1024 else { return } // 4MB limit

        let entry = Entry(data: data, timestamp: Date(), expirationTime: expirationTime)
        let nsKey = NSString(string: key)

        // Store in memory immediately for instant access
        memoryCache.setObject(entry, forKey: nsKey, cost: data.count)

        // Get file URL with cached hash computation for performance
        let fileURL = cachedFileURL(for: key)

        // Persist to disk async
        diskQueue.async {
            self.saveEntryToDisk(entry, at: fileURL)
        }
    }

    // MARK: - Disk Operations (nonisolated for performance)

    nonisolated func fileURL(for key: String) -> URL {
        // Direct SHA256 computation for filename generation
        let fileName = key.sha256Hash
        return cacheDirectory.appendingPathComponent(fileName)
    }

    func cachedFileURL(for key: String) -> URL {
        // Use cached SHA256 hash to avoid recomputation in hot paths
        let fileName: String
        if let cached = keyCache[key] {
            fileName = cached
        } else {
            fileName = key.sha256Hash
            keyCache[key] = fileName
            // Prevent unbounded memory growth by clearing cache when limit reached
            if keyCache.count > 1000 {
                keyCache.removeAll(keepingCapacity: true)
            }
        }
        return cacheDirectory.appendingPathComponent(fileName)
    }

    nonisolated func saveEntryToDisk(_ entry: Entry, at url: URL) {
        let metadata = CacheMetadata(
            timestamp: entry.timestamp,
            expirationTime: entry.expirationTime,
            dataSize: entry.data.count
        )

        do {
            let metadataData = try JSONEncoder().encode(metadata)
            let combined = metadataData + dataSeparator + entry.data
            try combined.write(to: url)
        } catch {
            // Silent fail - cache miss on next read
        }
    }

    nonisolated func loadEntryFromDisk(at url: URL) -> Entry? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        // Find separator
        guard let separatorRange = data.range(of: dataSeparator) else { return nil }

        let metadataData = data[..<separatorRange.lowerBound]
        let entryData = data[separatorRange.upperBound...]

        guard let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: metadataData) else {
            return nil
        }

        return Entry(
            data: Data(entryData),
            timestamp: metadata.timestamp,
            expirationTime: metadata.expirationTime
        )
    }

    // MARK: - HTTP Cache Headers Parsing

    /// Calculates effective expiration time prioritizing HTTP response headers over config
    /// - Parameters:
    ///   - response: HTTP response containing cache headers
    ///   - fallbackTime: Fallback expiration time from cache configuration
    /// - Returns: Effective expiration time in seconds, or nil if never expires
    func calculateEffectiveExpirationTime(fromResponse response: HTTPURLResponse?, fallbackTime: TimeInterval?) -> TimeInterval? {
        guard let response = response else { return fallbackTime }

        let headers = response.allHeaderFields

        // 1. Check Cache-Control directives (highest priority)
        if let cacheControl = headers["Cache-Control"] as? String {
            let result = parseCacheControlDirectives(cacheControl)
            
            // Handle no-cache/no-store (immediate expiration)
            if result.noCache || result.noStore {
                return 0
            }
            
            // Use max-age if available
            if let maxAge = result.maxAge {
                return TimeInterval(maxAge)
            }
        }

        // 2. Check Expires header (medium priority)
        if let expiresString = headers["Expires"] as? String {
            if let expirationTime = parseExpiresHeader(expiresString) {
                return expirationTime
            }
        }

        // 3. Fallback to configuration (lowest priority)
        return fallbackTime
    }

    /// Parses Cache-Control header directives
    /// - Parameter cacheControl: Cache-Control header value
    /// - Returns: Parsed cache control directives
    private func parseCacheControlDirectives(_ cacheControl: String) -> CacheControlDirectives {
        let directives = cacheControl.lowercased().components(separatedBy: ",")
        var result = CacheControlDirectives()
        
        for directive in directives {
            let trimmed = directive.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmed.hasPrefix("max-age=") {
                let maxAgeString = String(trimmed.dropFirst(8))
                result.maxAge = Int(maxAgeString)
            } else if trimmed == "no-cache" {
                result.noCache = true
            } else if trimmed == "no-store" {
                result.noStore = true
            } else if trimmed == "must-revalidate" {
                result.mustRevalidate = true
            } else if trimmed.hasPrefix("s-maxage=") {
                let sMaxAgeString = String(trimmed.dropFirst(10))
                result.sMaxAge = Int(sMaxAgeString)
            }
        }
        
        return result
    }

    /// Shared date formatter for optimal performance
    /// Uses en_US_POSIX locale and UTC timezone as per HTTP standards
    private static let expiresDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // Explicit UTC
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()
    
    /// Parses Expires header to calculate expiration time from now
    /// - Parameter expiresString: Expires header value (RFC 7234 format)
    /// - Returns: Expiration time in seconds from now, or nil if invalid
    private func parseExpiresHeader(_ expiresString: String) -> TimeInterval? {
        let formatter = Self.expiresDateFormatter
        
        // Try common date formats in order of likelihood
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",  // RFC 7234 (most common)
            "EEEE, dd-MMM-yy HH:mm:ss zzz",   // RFC 850 (obsolete)
            "EEE MMM d HH:mm:ss yyyy",        // ANSI C asctime()
            "EEE, dd-MMM-yyyy HH:mm:ss zzz"   // Common variant
        ]

        for format in formats {
            formatter.dateFormat = format
            if let expirationDate = formatter.date(from: expiresString) {
                let timeInterval = expirationDate.timeIntervalSinceNow
                return max(timeInterval, 0) // Don't allow negative expiration
            }
        }

        return nil
    }
}

// MARK: - Supporting Types

/// Cache-Control directive parsing result
private struct CacheControlDirectives {
    var maxAge: Int?
    var sMaxAge: Int?
    var noCache = false
    var noStore = false
    var mustRevalidate = false
}

private struct CacheMetadata: Codable {
    let timestamp: Date
    let expirationTime: TimeInterval?
    let dataSize: Int
}
