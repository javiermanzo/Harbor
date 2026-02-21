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
        /// Use URLCache - Apple's built-in HTTP cache with automatic ETag/304 support.
        /// This is the default and recommended option for most use cases.
        /// Benefits: Automatic ETag handling, 304 responses, Cache-Control compliance.
        case urlCache
        
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
        
        /// Get custom configuration if using custom cache
        var customConfiguration: Configuration? {
            switch self {
            case .custom(let config):
                return config
            default:
                return nil
            }
        }
    }
}
