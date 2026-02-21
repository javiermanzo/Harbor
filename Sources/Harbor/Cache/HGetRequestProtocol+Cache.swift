//
//  HGetRequestProtocol+Cache.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import Foundation

public extension HGetRequestProtocol {

    /// Retrieves cached data for this request using the associated Model type.
    /// Only works with custom cache policy. For URLCache, use standard request methods.
    /// - Returns: The cached model if found and valid, `nil` otherwise.
    func cache() async -> Model? {
        guard case .custom(let config) = cachePolicy,
              let cacheKey else { return nil }
        return await HCache.Manager.shared.getCachedData(forKey: cacheKey, type: Model.self, config: config)
    }

    /// Clears cached data for this specific request.
    /// Works with both URLCache and custom cache policies.
    func clearCache() async {
        guard let cacheKey else { return }
        
        switch cachePolicy {
        case .urlCache(let urlCache):
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

extension HGetRequestProtocol {
    /// Generates a cache key for this request based on the complete URL.
    var cacheKey: String? {
        let compositeURL: URL? = HURLBuilder.compositeURL(url: url,
                                                          pathParameters: pathParameters,
                                                          queryParameters: queryParameters)

        return compositeURL?.absoluteString
    }
}

