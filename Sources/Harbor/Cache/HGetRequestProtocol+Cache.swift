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
        // Support legacy cacheConfiguration if set
        let effectivePolicy = resolveEffectivePolicy()
        
        guard case .custom(let config) = effectivePolicy,
              let cacheKey else { return nil }
        return await HCache.Manager.shared.getCachedData(forKey: cacheKey, type: Model.self, config: config)
    }

    /// Clears cached data for this specific request.
    /// Only works with custom cache policy.
    func clearCache() async {
        let effectivePolicy = resolveEffectivePolicy()
        
        guard case .custom = effectivePolicy else {
            // URLCache - clearing is handled by URLCache automatically
            return
        }
        
        guard let cacheKey else { return }
        await HCache.Manager.shared.removeCachedData(for: cacheKey)
    }
    
    /// Resolves effective cache policy, supporting deprecated cacheConfiguration
    private func resolveEffectivePolicy() -> HCache.Policy {
        // If legacy cacheConfiguration is set, use it
        if let config = cacheConfiguration {
            return .custom(config)
        }
        // Otherwise use new cachePolicy
        return cachePolicy
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

