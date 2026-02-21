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
        /// Use URLCache with automatic ETag/304 support.
        /// Default uses URLCache.shared. Pass custom URLCache for specific memory/disk limits.
        case urlCache(URLCache = .shared)

        /// Use Harbor's custom cache system with full control over expiration and storage.
        case custom(Configuration)
        
        /// No caching - always fetch fresh data from network.
        case disabled
        
        /// Whether caching is enabled for this policy.
        var isCachingEnabled: Bool {
            switch self {
            case .urlCache, .custom:
                return true
            case .disabled:
                return false
            }
        }
        
        // MARK: - Equatable
        
        public static func == (lhs: Policy, rhs: Policy) -> Bool {
            switch (lhs, rhs) {
            case (.urlCache(let lCache), .urlCache(let rCache)):
                return lCache.memoryCapacity == rCache.memoryCapacity &&
                       lCache.diskCapacity == rCache.diskCapacity
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
