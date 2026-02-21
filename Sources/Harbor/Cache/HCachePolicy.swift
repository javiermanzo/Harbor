//
//  HCachePolicy.swift
//  Harbor
//
//  Created by Javier Manzo on 20/02/2026.
//

import Foundation

public extension HCache {
    /// Defines the caching strategy for network requests.
    enum Policy: Sendable, Equatable {
        /// Use URLCache with optional custom configuration - automatic ETag/304 support.
        /// Pass nil for default configuration (50MB memory, 200MB disk).
        /// Pass custom URLCache for specific memory/disk limits.
        /// This is the default and recommended option for most use cases.
        /// Benefits: Automatic ETag handling, 304 responses, Cache-Control compliance.
        case urlCache(URLCache = URLCache.shared)

        /// Use Harbor's custom cache system with full control over expiration and storage.
        /// Use this when you need: Custom TTL, size limits, manual cache invalidation.
        /// Note: Does not support ETags automatically - server will send full response each time.
        case custom(Configuration)
        
        /// No caching - always fetch fresh data from network.
        case disabled
        
        /// Convenience property to check if caching is enabled
        var isCachingEnabled: Bool {
            switch self {
            case .urlCache, .custom:
                return true
            case .disabled:
                return false
            }
        }
        
        /// Get custom URLCache if provided
        var customURLCache: URLCache? {
            switch self {
            case .urlCache(let cache):
                return cache
            default:
                return nil
            }
        }
        
        /// Get custom configuration if using custom cache
        var customConfiguration: Configuration? {
            switch self {
            case .custom(let config):
                return config
            default:
                return nil
            }
        }
        
        // MARK: - Equatable
        
        public static func == (lhs: Policy, rhs: Policy) -> Bool {
            switch (lhs, rhs) {
            case (.urlCache(let lCache), .urlCache(let rCache)):
                // URLCache no es Equatable, comparamos por configuración
                return lCache?.memoryCapacity == rCache?.memoryCapacity &&
                       lCache?.diskCapacity == rCache?.diskCapacity
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
