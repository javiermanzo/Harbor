//
//  HCacheManager.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import Foundation

public enum HCache {}

extension HCache {
    /// High-performance file-based cache manager using a single-file strategy (Codable Wrapper).
    /// Provides granular control over expiration that URLCache cannot easily offer.
    @HRequestManagerActor
    final class Manager: Sendable {
        
        /// Shared instance of the cache manager.
        static let shared = Manager()
        
        /// Fast in-memory cache (L1)
        private let memoryCache = NSCache<NSString, Entry>()
        
        /// Cache directory for persistence (L2)
        let cacheDirectory: URL
        
        /// Background queue for disk operations to avoid blocking main thread
        let diskQueue = DispatchQueue(label: "harbor.cache.disk", qos: .utility)
        
        private init() {
            // 1. Setup cache directory safely in Library/Caches
            guard let systemCacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                self.cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("HarborCache")
                return
            }
            
            self.cacheDirectory = systemCacheDir.appendingPathComponent("HarborCache", isDirectory: true)
            
            // 2. Create directory
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            
            // 3. Configure NSCache limits (default 100MB, will be updated per-request)
            memoryCache.totalCostLimit = 100 * 1024 * 1024
            memoryCache.countLimit = 500
            
            // 4. Perform background cleanup
            let dir = self.cacheDirectory
            Task.detached(priority: .background) {
                FileStorage.cleanupExpiredFiles(at: dir)
            }
        }
        
        // MARK: - Public API
        
        /// Retrieves cached data by key (for custom cache type).
        func getCachedData<T: HModel>(forKey key: String, type: T.Type, config: HCache.Configuration) async -> T? {
            return await getCachedData(for: key, type: type, maxAge: config.expirationTime)
        }
        
        /// Stores data by key (for custom cache type).
        func storeData(_ data: Data, forKey key: String, config: HCache.Configuration, response: HTTPURLResponse?) async {
            let effectiveExpirationTime = calculateEffectiveExpirationTime(
                fromResponse: response,
                fallbackTime: config.expirationTime
            )
            
            await storeData(data, for: key, expirationTime: effectiveExpirationTime, maxObjectSize: config.maxObjectSizeInBytes)
        }
        
        /// Clears all cached data.
        func clearAllCache() {
            memoryCache.removeAllObjects()
            
            diskQueue.async {
                try? FileManager.default.removeItem(at: self.cacheDirectory)
                try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
            }
        }
        
        /// Removes specific cached data.
        func removeCachedData(for key: String) {
            memoryCache.removeObject(forKey: NSString(string: key))
            
            let dir = self.cacheDirectory
            diskQueue.async {
                let fileURL = FileStorage.url(for: key, in: dir)
                try? FileManager.default.removeItem(at: fileURL)
                
                // Cleanup legacy files if present
                let legacyURLs = FileStorage.legacyUrls(for: key, in: dir)
                try? FileManager.default.removeItem(at: legacyURLs.0)
                try? FileManager.default.removeItem(at: legacyURLs.1)
            }
        }
        
        // MARK: - Core Logic
        
        private func getCachedData<T: HModel>(for key: String, type: T.Type, maxAge: TimeInterval?) async -> T? {
            let nsKey = NSString(string: key)
            
            // 🚀 L1: Memory Cache
            if let entry = memoryCache.object(forKey: nsKey) {
                if !entry.isExpired(maxAge: maxAge) {
                    return try? JSONDecoder().decode(type, from: entry.data)
                } else {
                    memoryCache.removeObject(forKey: nsKey)
                }
            }
            
            // 💾 L2: Disk Cache
            return await withCheckedContinuation { continuation in
                let dir = self.cacheDirectory
                
                diskQueue.async { [key] in
                    let fileURL = FileStorage.url(for: key, in: dir)
                    
                    guard let fileData = try? Data(contentsOf: fileURL),
                          let diskEntry = try? JSONDecoder().decode(DiskEntry.self, from: fileData) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Check expiration
                    if diskEntry.isExpired(maxAge: maxAge) {
                        try? FileManager.default.removeItem(at: fileURL)
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Decode Model
                    do {
                        let model = try JSONDecoder().decode(type, from: diskEntry.data)
                        
                        // Promote to Memory Cache
                        let entry = Entry(data: diskEntry.data, timestamp: diskEntry.timestamp, expirationTime: diskEntry.expirationTime)

                        Task { @HRequestManagerActor [weak self] in
                            self?.memoryCache.setObject(entry, forKey: NSString(string: key), cost: diskEntry.data.count)
                        }
                        
                        continuation.resume(returning: model)
                    } catch {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        
        private func storeData(_ data: Data, for key: String, expirationTime: TimeInterval?, maxObjectSize: Int) async {
            guard data.count < maxObjectSize else { return }
            
            let entry = Entry(data: data, timestamp: Date(), expirationTime: expirationTime)
            let nsKey = NSString(string: key)
            
            // Update Memory
            memoryCache.setObject(entry, forKey: nsKey, cost: data.count)
            
            // Persist to Disk
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let dir = self.cacheDirectory
                diskQueue.async {
                    let fileURL = FileStorage.url(for: key, in: dir)
                    let diskEntry = DiskEntry(data: data, timestamp: entry.timestamp, expirationTime: entry.expirationTime)
                    
                    do {
                        let encodedEntry = try JSONEncoder().encode(diskEntry)
                        try encodedEntry.write(to: fileURL)
                        
                        // Cleanup legacy files just in case they exist for this key
                        let legacyURLs = FileStorage.legacyUrls(for: key, in: dir)
                        try? FileManager.default.removeItem(at: legacyURLs.0) // data
                        try? FileManager.default.removeItem(at: legacyURLs.1) // .meta
                    } catch {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                    continuation.resume()
                }
            }
        }
        
        // MARK: - Expiration Logic
        
        func calculateEffectiveExpirationTime(fromResponse response: HTTPURLResponse?, fallbackTime: TimeInterval?) -> TimeInterval? {
            guard let response = response else { return fallbackTime }
            let headers = response.allHeaderFields
            
            if let cacheControl = headers["Cache-Control"] as? String {
                let directives = parseCacheControlDirectives(cacheControl)
                if directives.noCache || directives.noStore { return 0 }
                if let maxAge = directives.maxAge { return TimeInterval(maxAge) }
            }
            
            if let expiresString = headers["Expires"] as? String,
               let expiresDate = parseExpiresHeader(expiresString) {
                return max(expiresDate.timeIntervalSinceNow, 0)
            }
            
            return fallbackTime
        }
        
        private func parseCacheControlDirectives(_ cacheControl: String) -> CacheControlDirectives {
             let directives = cacheControl.lowercased().components(separatedBy: ",")
             var result = CacheControlDirectives()
             
             for directive in directives {
                 let trimmed = directive.trimmingCharacters(in: .whitespacesAndNewlines)
                 if trimmed.hasPrefix("max-age=") {
                     result.maxAge = Int(String(trimmed.dropFirst(8)))
                 } else if trimmed == "no-cache" {
                     result.noCache = true
                 } else if trimmed == "no-store" {
                     result.noStore = true
                 }
             }
             return result
         }
        
        private static let expiresDateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter
        }()
        
        private func parseExpiresHeader(_ expiresString: String) -> Date? {
            let formatter = Self.expiresDateFormatter
            let formats = [
                "EEE, dd MMM yyyy HH:mm:ss zzz",
                "EEEE, dd-MMM-yy HH:mm:ss zzz",
                "EEE MMM d HH:mm:ss yyyy"
            ]
            for format in formats {
                formatter.dateFormat = format
                if let date = formatter.date(from: expiresString) { return date }
            }
            return nil
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
            
            // 1. Cleanup new format (.cache)
            let cacheFiles = resourceKeys.filter { $0.pathExtension == "cache" }
            for fileURL in cacheFiles {
                guard let data = try? Data(contentsOf: fileURL),
                      let diskEntry = try? JSONDecoder().decode(DiskEntry.self, from: data) else {
                    // Corrupted file? Remove it
                    try? FileManager.default.removeItem(at: fileURL)
                    continue
                }
                
                if diskEntry.isExpired(maxAge: nil) {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            
            // 2. Cleanup legacy format (.meta)
            let metaFiles = resourceKeys.filter { $0.pathExtension == "meta" }
            for metaURL in metaFiles {
                // We proactively remove legacy files during cleanup to migrate to new system over time
                // or we can let them expire naturally. For now, let's just expire them.
                // Assuming legacy CacheMetadata struct is no longer available here, we parse broadly or just delete.
                // Since we removed CacheMetadata struct, we'll just delete legacy files to force refresh.
                let dataURL = metaURL.deletingPathExtension()
                try? FileManager.default.removeItem(at: metaURL)
                try? FileManager.default.removeItem(at: dataURL)
            }
        }
    }
}

// MARK: - Supporting Types

private struct CacheControlDirectives {
    var maxAge: Int?
    var noCache = false
    var noStore = false
}

/// Disk persistence wrapper containing both data and metadata in a single file.
private struct DiskEntry: Codable {
    let data: Data
    let timestamp: Date
    let expirationTime: TimeInterval?
    
    func isExpired(maxAge: TimeInterval?) -> Bool {
        let effectiveMaxAge = expirationTime ?? maxAge
        guard let maxAge = effectiveMaxAge else { return false }
        return Date().timeIntervalSince(timestamp) > maxAge
    }
}
