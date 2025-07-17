//
//  HCacheManager.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import Foundation

public enum HCache {}

extension HCache {
    /// Manages caching for Harbor requests using a hybrid URLSession + NSCache approach.
    /// Provides thread-safe caching with automatic expiration handling and memory optimization.
    @HRequestManagerActor
    final class Manager: Sendable {
        /// Debouncer for UserDefaults operations to reduce I/O
        private var saveKeysTask: Task<Void, Never>?

        /// Shared instance of the cache manager.
        static let shared = Manager()

        /// In-memory cache for fast access to frequently used data.
        private let memoryCache = NSCache<NSString, Entry>()

        /// URLSession cache for persistent HTTP-level caching.
        let urlSessionCache: URLCache

        /// Set of cached keys for tracking persisted cache entries.
        private var cachedKeys: Set<String> = []

        /// UserDefaults key for storing cached keys.
        private let cachedKeysUserDefaultsKey = "harbor_cache_keys"

        /// Returns the current URLSession cache instance for configuration.
        var currentURLSessionCache: URLCache {
            return urlSessionCache
        }

        private init() {
            let capacityMBsMemory: Int = HRequestManager.config.defaultMemoryCacheCapacity
            let capacityMBsDisk: Int = HRequestManager.config.defaultDiskCacheCapacity

            self.urlSessionCache = URLCache(
                memoryCapacity: 0, // No memory cache in URLSession - use NSCache instead
                diskCapacity: capacityMBsDisk * 1024 * 1024,
                diskPath: "harbor_cache"
            )

            // Configure NSCache for optimal memory management with automatic eviction
            memoryCache.totalCostLimit = capacityMBsMemory * 1024 * 1024
            memoryCache.countLimit = 2000
            memoryCache.evictsObjectsWithDiscardedContent = true

            // Load persisted cache asynchronously to avoid blocking initialization
            Task {
                await loadPersistedCacheIntoMemory()
            }
        }

        /// Retrieves cached data for a request with result protocol.
        /// - Parameter request: The request object with associated model type.
        /// - Returns: The decoded model if found and valid, `nil` otherwise.
        func getCachedData<Request: HGetRequestProtocol>(for request: Request) async -> Request.Model? {
            // Get effective cache configuration (request.cache or default from config)
            let defaultConfig = HRequestManager.config.defaultCacheConfiguration
            let effectiveCacheConfig = request.cacheConfiguration ?? defaultConfig

            // Return nil if caching is disabled
            guard effectiveCacheConfig.isEnabled,
                  let cacheKey = request.cacheKey else {
                return nil
            }

            return getCachedData(for: cacheKey, type: Request.Model.self, maxAge: effectiveCacheConfig.expirationTime)
        }

        /// Stores data for a request if caching is enabled.
        /// - Parameters:
        ///   - data: The response data to cache.
        ///   - request: The HRequestWithResultProtocol request object.
        ///   - response: The HTTP URL response for URLSession cache.
        func storeData(_ data: Data, for request: any HGetRequestProtocol, response: HTTPURLResponse?) async {
            // Get effective cache configuration (request.cache or default from config)
            let defaultConfig = HRequestManager.config.defaultCacheConfiguration
            let effectiveCacheConfig = request.cacheConfiguration ?? defaultConfig

            // Only store if caching is enabled
            guard effectiveCacheConfig.isEnabled,
                  let cacheKey = request.cacheKey else { return }

            storeData(data, for: cacheKey, response: response, expirationTime: effectiveCacheConfig.expirationTime)
        }

        /// Clears all cached data from both memory and URLSession caches.
        func clearAllCache() {
            memoryCache.removeAllObjects()
            urlSessionCache.removeAllCachedResponses()
            cachedKeys.removeAll()
            saveCachedKeys()
        }

        /// Removes cached data for a specific key from both caches.
        /// - Parameter key: The cache key to remove.
        func removeCachedData(for key: String) {
            let nsKey = NSString(string: key)

            // Remove from memory cache
            memoryCache.removeObject(forKey: nsKey)

            // Remove from URLSession cache
            if let url = URL(string: key) {
                let request = URLRequest(url: url)
                urlSessionCache.removeCachedResponse(for: request)
            }

            // Remove from tracking set
            cachedKeys.remove(key)
        }
    }
}

private extension HCache.Manager {

    /// Loads persisted cache data from URLSession cache into memory cache on initialization.
    /// Automatically removes expired entries during the loading process.
    private func loadPersistedCacheIntoMemory() async {
        // Load cached keys from UserDefaults on background queue
        let storedKeys = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let keys = UserDefaults.standard.array(forKey: self.cachedKeysUserDefaultsKey) as? [String]
                continuation.resume(returning: keys)
            }
        }

        guard let storedKeys = storedKeys else {
            return
        }

        cachedKeys = Set(storedKeys)
        var validKeys: Set<String> = []

        // Process cached keys in sorted order (most recent first)
        let sortedKeys = cachedKeys.sorted()

        for key in sortedKeys {
            // Validate URL
            guard let url = URL(string: key) else {
                cachedKeys.remove(key)
                continue
            }

            // Check URLSession cache
            let request = URLRequest(url: url)
            guard let cachedResponse = urlSessionCache.cachedResponse(for: request) else {
                cachedKeys.remove(key)
                continue
            }

            // Validate timestamp
            guard let timestamp = cachedResponse.userInfo?["timestamp"] as? Date else {
                urlSessionCache.removeCachedResponse(for: request)
                cachedKeys.remove(key)
                continue
            }

            // Get the stored expiration time for this cache entry
            let storedExpirationTime = cachedResponse.userInfo?["expirationTime"] as? TimeInterval

            // Check if entry is expired
            if isExpired(timestamp: timestamp, expirationTime: storedExpirationTime) {
                removeExpiredEntry(key: key, request: request)
                continue
            }

            // Valid entry - load into memory cache only if data is reasonable size
            if cachedResponse.data.count < 2 * 1024 * 1024 { // Max 2MB per entry
                let entry = Entry(data: cachedResponse.data, timestamp: timestamp)
                let nsKey = NSString(string: key)
                memoryCache.setObject(entry, forKey: nsKey, cost: cachedResponse.data.count)
            }

            validKeys.insert(key)
        }

        // Update keys index with only valid keys
        cachedKeys = validKeys
        saveCachedKeys()
    }

    /// Saves the current cached keys to UserDefaults for persistence.
    /// Uses async dispatch to avoid blocking the main thread.
    func saveCachedKeys() {
        let keysArray = Array(cachedKeys)
        DispatchQueue.global(qos: .utility).async {
            UserDefaults.standard.set(keysArray, forKey: self.cachedKeysUserDefaultsKey)
        }
    }

    /// Debounced save operation to reduce UserDefaults I/O
    func debouncedSaveCachedKeys() async {
        // Cancel previous save task
        saveKeysTask?.cancel()

        // Create new debounced save task
        saveKeysTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second debounce
            guard !Task.isCancelled else { return }
            saveCachedKeys()
        }

        await saveKeysTask?.value
    }

    /// Retrieves cached data for the given key if available and not expired.
    /// OPTIMIZED: Memory-first strategy for maximum performance.
    /// - Parameters:
    ///   - key: The cache key (typically the complete URL).
    ///   - type: The model type to decode the cached data into.
    ///   - maxAge: Maximum age for the cached data in seconds. If nil, entry never expires.
    /// - Returns: The decoded model if found and valid, `nil` otherwise.
    func getCachedData<T: HModel>(for key: String, type: T.Type, maxAge: TimeInterval?) -> T? {
        let nsKey = NSString(string: key)

        // 🚀 FASTEST PATH: Check NSCache first (direct memory access)
        if let entry = memoryCache.object(forKey: nsKey) {
            if !entry.isExpired(maxAge: maxAge) {
                // Cache hit: Decode directly from cached entry
                do {
                    return try JSONDecoder().decode(type, from: entry.data)
                } catch {
                    // Corrupted - remove and continue to disk fallback
                    memoryCache.removeObject(forKey: nsKey)
                }
            } else {
                // Expired - remove from memory and check disk
                memoryCache.removeObject(forKey: nsKey)
            }
        }

        // Cache miss: Check disk cache and promote to memory
        guard let url = URL(string: key) else { return nil }

        let request = URLRequest(url: url)
        guard let cachedResponse = urlSessionCache.cachedResponse(for: request),
              let timestamp = cachedResponse.userInfo?["timestamp"] as? Date else {
            return nil
        }

        // Get the stored expiration time for this cache entry
        let storedExpirationTime = cachedResponse.userInfo?["expirationTime"] as? TimeInterval
        let effectiveExpirationTime = storedExpirationTime ?? maxAge

        // Check if entry is expired
        if isExpired(timestamp: timestamp, expirationTime: effectiveExpirationTime) {
            removeExpiredEntry(key: key, request: request)
            return nil
        }

        do {
            let model = try JSONDecoder().decode(type, from: cachedResponse.data)
            // PROMOTE: Load into fast memory cache for next time
            let entry = Entry(data: cachedResponse.data, timestamp: timestamp)
            memoryCache.setObject(entry, forKey: nsKey, cost: cachedResponse.data.count)
            return model
        } catch {
            removeCachedData(for: key)
            return nil
        }
    }

    /// Stores data in both memory and URLSession caches with size validation.
    /// - Parameters:
    ///   - data: The response data to cache.
    ///   - key: The cache key (typically the complete URL).
    ///   - response: The HTTP URL response for URLSession cache.
    ///   - expirationTime: The expiration time for this cache entry. If nil, entry never expires.
    func storeData(_ data: Data, for key: String, response: HTTPURLResponse?, expirationTime: TimeInterval?) {
        // Skip caching if data is too large (>2MB)
        guard data.count < 2 * 1024 * 1024 else { return }

        let nsKey = NSString(string: key)
        let timestamp = Date()

        // Store in memory cache for fast access
        let entry = Entry(data: data, timestamp: timestamp)
        memoryCache.setObject(entry, forKey: nsKey, cost: data.count)

        // Store in URLSession cache for persistence
        if let url = URL(string: key), let httpResponse = response {
            let request = URLRequest(url: url)
            var userInfo: [AnyHashable: Any] = [
                "timestamp": timestamp,
                "content-length": data.count
            ]

            // Store expiration time if provided
            if let expirationTime {
                userInfo["expirationTime"] = expirationTime
            }

            let cachedResponse = CachedURLResponse(
                response: httpResponse,
                data: data,
                userInfo: userInfo,
                storagePolicy: .allowed
            )

            urlSessionCache.storeCachedResponse(cachedResponse, for: request)

            // Add key to tracking set
            cachedKeys.insert(key)

            // Batch UserDefaults saves for better performance
            Task {
                await debouncedSaveCachedKeys()
            }
        }
    }

    /// Removes an expired cache entry from both memory cache, URLSession cache, and tracking set.
    /// - Parameters:
    ///   - key: The cache key to remove.
    ///   - request: The URLRequest for URLSession cache removal.
    func removeExpiredEntry(key: String, request: URLRequest) {
        let nsKey = NSString(string: key)

        // Remove from memory cache
        memoryCache.removeObject(forKey: nsKey)

        // Remove from URLSession cache
        urlSessionCache.removeCachedResponse(for: request)

        // Remove from tracking set
        cachedKeys.remove(key)
    }

    /// Checks if a cache entry is expired based on its timestamp and expiration time.
    /// - Parameters:
    ///   - timestamp: The timestamp when the entry was created.
    ///   - expirationTime: The expiration time in seconds. If nil, entry never expires.
    /// - Returns: `true` if the entry is expired, `false` otherwise.
    func isExpired(timestamp: Date, expirationTime: TimeInterval?) -> Bool {
        guard let expirationTime = expirationTime else {
            // If no expiration time is set, the entry never expires
            return false
        }

        let age = Date().timeIntervalSince(timestamp)
        return age > expirationTime
    }
}
