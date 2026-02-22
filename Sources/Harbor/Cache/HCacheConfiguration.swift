//
//  HCacheConfiguration.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import Foundation

public extension HCache {
    /// Configuration for custom cache behavior.
    /// Used with `.custom(Configuration)` cacheType.
    struct Configuration: Sendable, Equatable {
        /// Cache expiration time in seconds. Nil means no expiration.
        public let expirationTime: TimeInterval?
        
        /// Maximum object size in megabytes. Objects larger than this won't be cached.
        public let maxObjectSizeInMBs: Int
        
        /// Memory cache capacity in megabytes for L1 cache.
        public let memoryCacheCapacityInMBs: Int
        
        /// Creates a cache configuration.
        /// - Parameters:
        ///   - expirationTime: Time in seconds before cache expires. Default: 1 week.
        ///   - maxObjectSizeInMBs: Maximum object size in MB. Default: 10 MB.
        ///   - memoryCacheCapacityInMBs: Memory cache capacity in MB. Default: 100 MB.
        public init(
            expirationTime: TimeInterval? = .oneWeek,
            maxObjectSizeInMBs: Int = 10,
            memoryCacheCapacityInMBs: Int = 100
        ) {
            self.expirationTime = expirationTime
            self.maxObjectSizeInMBs = maxObjectSizeInMBs
            self.memoryCacheCapacityInMBs = memoryCacheCapacityInMBs
        }
        
        /// Maximum object size in bytes.
        var maxObjectSizeInBytes: Int {
            return maxObjectSizeInMBs * 1024 * 1024
        }
        
        /// Memory cache capacity in bytes.
        var memoryCacheCapacityInBytes: Int {
            return memoryCacheCapacityInMBs * 1024 * 1024
        }
    }
}
