//
//  HCacheManager.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import Foundation

public enum HCache {}

extension HCache {
    /// High-performance file-based cache manager using two-file strategy (Data + Metadata).
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
            
            // 3. Configure NSCache limits
            let memoryMB = HRequestManager.config.defaultMemoryCacheCapacity
            memoryCache.totalCostLimit = memoryMB * 1024 * 1024
            memoryCache.countLimit = 500
            
            // 4. Perform background cleanup
            let dir = self.cacheDirectory
            diskQueue.async {
                FileStorage.cleanupExpiredFiles(at: dir)
            }
        }
        
        // MARK: - Public API
        
        /// Retrieves cached data for a request.
        func getCachedData<Request: HGetRequestProtocol>(for request: Request) async -> Request.Model? {
            let config = request.cacheConfiguration ?? HRequestManager.config.defaultCacheConfiguration
            guard config.isEnabled, let key = request.cacheKey else { return nil }
            
            return await getCachedData(for: key, type: Request.Model.self, maxAge: config.expirationTime)
        }
        
        /// Stores data for a request.
        func storeData(_ data: Data, for request: any HGetRequestProtocol, response: HTTPURLResponse?) async {
            let config = request.cacheConfiguration ?? HRequestManager.config.defaultCacheConfiguration
            guard config.isEnabled, let key = request.cacheKey else { return }
            
            let effectiveExpirationTime = calculateEffectiveExpirationTime(
                fromResponse: response,
                fallbackTime: config.expirationTime
            )
            
            await storeData(data, for: key, expirationTime: effectiveExpirationTime)
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
                let (dataURL, metaURL) = FileStorage.urls(for: key, in: dir)
                try? FileManager.default.removeItem(at: dataURL)
                try? FileManager.default.removeItem(at: metaURL)
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
                diskQueue.async {
                    // 1. Resolve URLs
                    let (dataURL, metaURL) = FileStorage.urls(for: key, in: dir)
                    
                    // 2. Read Metadata first
                    guard let metaData = try? Data(contentsOf: metaURL),
                          let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: metaData) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // 3. Check expiration
                    let entryForCheck = Entry(data: Data(), timestamp: metadata.timestamp, expirationTime: metadata.expirationTime)
                    if entryForCheck.isExpired(maxAge: maxAge) {
                        try? FileManager.default.removeItem(at: dataURL)
                        try? FileManager.default.removeItem(at: metaURL)
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // 4. Read Data
                    guard let data = try? Data(contentsOf: dataURL) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // 5. Decode & Promote
                    do {
                        let model = try JSONDecoder().decode(type, from: data)
                        let entry = Entry(data: data, timestamp: metadata.timestamp, expirationTime: metadata.expirationTime)
                        
                        Task { @HRequestManagerActor in
                            let nsKey = NSString(string: key)
                            self.memoryCache.setObject(entry, forKey: nsKey, cost: data.count)
                        }
                        
                        continuation.resume(returning: model)
                    } catch {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        
        private func storeData(_ data: Data, for key: String, expirationTime: TimeInterval?) async {
            guard data.count < 50 * 1024 * 1024 else { return } // 50MB limit
            
            let entry = Entry(data: data, timestamp: Date(), expirationTime: expirationTime)
            let nsKey = NSString(string: key)
            
            // Update Memory
            memoryCache.setObject(entry, forKey: nsKey, cost: data.count)
            
            // Persist to Disk
            let dir = self.cacheDirectory
            diskQueue.async {
                let (dataURL, metaURL) = FileStorage.urls(for: key, in: dir)
                let metadata = CacheMetadata(timestamp: entry.timestamp, expirationTime: entry.expirationTime, dataSize: data.count)
                
                do {
                    try data.write(to: dataURL)
                    let metaData = try JSONEncoder().encode(metadata)
                    try metaData.write(to: metaURL)
                } catch {
                    try? FileManager.default.removeItem(at: dataURL)
                    try? FileManager.default.removeItem(at: metaURL)
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
        static func urls(for key: String, in directory: URL) -> (URL, URL) {
            let hash = key.sha256Hash
            let dataURL = directory.appendingPathComponent(hash)
            let metaURL = dataURL.appendingPathExtension("meta")
            return (dataURL, metaURL)
        }
        
        static func cleanupExpiredFiles(at directory: URL) {
            guard let resourceKeys = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
            
            let metaFiles = resourceKeys.filter { $0.pathExtension == "meta" }
            
            for metaURL in metaFiles {
                guard let data = try? Data(contentsOf: metaURL),
                      let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: data) else {
                    continue
                }
                
                if let expiration = metadata.expirationTime, Date().timeIntervalSince(metadata.timestamp) > expiration {
                    let dataURL = metaURL.deletingPathExtension()
                    try? FileManager.default.removeItem(at: metaURL)
                    try? FileManager.default.removeItem(at: dataURL)
                }
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

private struct CacheMetadata: Codable {
    let timestamp: Date
    let expirationTime: TimeInterval?
    let dataSize: Int
}
