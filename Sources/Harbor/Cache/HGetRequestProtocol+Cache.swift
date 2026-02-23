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
    /// - Returns: The cached model if found and valid, `nil` otherwise.
    func cache() async -> Model? {
        let effectiveCacheType: HCache.CacheType
        if let cacheType {
            effectiveCacheType = cacheType
        } else {
            effectiveCacheType = await HConfig.shared.defaultCacheType
        }
        
        switch effectiveCacheType {
        case .custom(let config):
            guard let cacheKey = await cacheKey() else { return nil }
            return await HCache.Manager.shared.getCachedData(forKey: cacheKey, type: Model.self, config: config)
            
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
    func saveCache(_ data: Data, response: HTTPURLResponse?) async {
        let requestCacheType = self.cacheType
        
        let effectiveCacheType: HCache.CacheType
        if let requestCacheType = requestCacheType {
            effectiveCacheType = requestCacheType
        } else {
            effectiveCacheType = await HConfig.shared.defaultCacheType
        }

        if case .custom(let config) = effectiveCacheType,
           let cacheKey = await cacheKey() {
            await HCache.Manager.shared.storeData(data, forKey: cacheKey, config: config, response: response)
        }
    }

    /// Returns the stored ETag for this request from the custom cache, if available.
    func cachedETag() async -> String? {
        guard let key = await cacheKey() else { return nil }
        return await HCache.Manager.shared.getETag(forKey: key)
    }

    /// Clears cached data for this specific request.
    /// Works with both URLCache and custom cache types.
    func clearCache() async {
        guard let cacheKey = await cacheKey() else { return }

        guard let cacheType else { return }

        switch cacheType {
        case .urlCache(let urlCache, _):
            // Remove from URLCache
            guard let url = URL(string: cacheKey) else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            urlCache.removeCachedResponse(for: request)
            
        case .custom:
            // Remove from custom cache
            await HCache.Manager.shared.removeCachedData(for: cacheKey)

        case .disabled:
            break
        }
    }
}

private extension HGetRequestProtocol {
    /// Builds and returns a URLRequest for this request.
    /// - Returns: The configured URLRequest, or nil if the request cannot be built.
    func urlRequest() async -> URLRequest? {
        await HURLBuilder.buildUrlRequest(request: self)
    }

    /// Generates a cache key for this request based on the complete URL.
    /// - Returns: The cache key string, or nil if the URL cannot be built.
    func cacheKey() async -> String? {
        let compositeURL: URL? = await HURLBuilder.compositeURL(url: url,
                                                          pathParameters: pathParameters,
                                                          queryParameters: queryParameters)

        return compositeURL?.absoluteString
    }
}
