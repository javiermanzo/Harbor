//
//  HCacheType.swift
//  Harbor
//
//  Created by Javier Manzo on 20/02/2026.
//

import Foundation

public extension HCache {
    /// Defines the caching type for network requests.
    enum CacheType: Sendable, Equatable {
        /// Use URLCache with automatic ETag/304 support.
        /// - Parameters:
        ///   - urlCache: The URLCache to use. Defaults to URLCache.shared.
        ///   - requestCachePolicy: The cache policy for requests. Defaults to .useProtocolCachePolicy.
        case urlCache(urlCache: URLCache = .shared, requestCachePolicy: NSURLRequest.CachePolicy = .useProtocolCachePolicy)

        /// Use Harbor's custom cache system with full control over expiration and storage.
        case custom(Configuration)
        
        /// No caching - always fetch fresh data from network.
        case disabled
        
        /// Whether caching is enabled for this type.
        var isCachingEnabled: Bool {
            switch self {
            case .urlCache, .custom:
                return true
            case .disabled:
                return false
            }
        }
        
        // MARK: - Equatable
        
        public static func == (lhs: CacheType, rhs: CacheType) -> Bool {
            switch (lhs, rhs) {
            case (.urlCache(let lCache, let lPolicy), .urlCache(let rCache, let rPolicy)):
                return lCache.memoryCapacity == rCache.memoryCapacity &&
                       lCache.diskCapacity == rCache.diskCapacity &&
                       lPolicy == rPolicy
            case (.disabled, .disabled):
                return true
            case (.custom(let lConfig), .custom(let rConfig)):
                return lConfig == rConfig
            default:
                return false
            }
        }
    }
}
