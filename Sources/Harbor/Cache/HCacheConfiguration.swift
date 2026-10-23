//
//  HCacheConfiguration.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import Foundation
import HarborCore

public extension HCache {
    /// Configuration for custom cache behavior.
    /// Used with `.custom(Configuration)` cacheType.
    struct Configuration: Sendable, Equatable {
        /// Fallback lifetime in seconds, used when a response gives none (`Cache-Control:
        /// max-age` or `Expires`). `nil` (`.noExpiration`) means no fallback: such responses
        /// never expire.
        public let expirationTime: TimeInterval?

        /// Maximum object size in megabytes. Objects larger than this won't be cached. Values below 1 are clamped to 1.
        public let maxObjectSizeInMBs: Int

        /// Memory cache capacity in megabytes for L1 cache. Values below 1 are clamped to 1.
        public let memoryCacheCapacityInMBs: Int

        /// Disk cache capacity in megabytes for L2 cache. When exceeded, the least recently used entries are evicted. Values below 1 are clamped to 1.
        /// The cache directory is shared by every request: the limit enforced is the largest
        /// capacity among the global default and the configurations used since it was set, so a
        /// per-request configuration can raise it but never shrinks the shared cache.
        public let diskCacheCapacityInMBs: Int

        /// Creates a cache configuration. Capacities are clamped to 1 MB and above, and to what
        /// fits in an `Int` of bytes (so `.max` means "as large as possible").
        /// - Parameters:
        ///   - expirationTime: Fallback lifetime in seconds for responses without one. Default: 1 week.
        ///   - maxObjectSizeInMBs: Maximum object size in MB. Default: 10 MB.
        ///   - memoryCacheCapacityInMBs: Memory cache capacity in MB. Default: 100 MB.
        ///   - diskCacheCapacityInMBs: Disk cache capacity in MB. Default: 100 MB.
        public init(
            expirationTime: TimeInterval? = .oneWeek,
            maxObjectSizeInMBs: Int = 10,
            memoryCacheCapacityInMBs: Int = 100,
            diskCacheCapacityInMBs: Int = 100
        ) {
            self.expirationTime = expirationTime
            self.maxObjectSizeInMBs = Self.clamped(maxObjectSizeInMBs)
            self.memoryCacheCapacityInMBs = Self.clamped(memoryCacheCapacityInMBs)
            self.diskCacheCapacityInMBs = Self.clamped(diskCacheCapacityInMBs)
        }

        /// Clamps a capacity in megabytes to `1...(Int.max / 1 MB)`, so its size in bytes never overflows.
        /// - Parameter megabytes: The requested capacity.
        private static func clamped(_ megabytes: Int) -> Int {
            min(max(1, megabytes), Int.max / (1024 * 1024))
        }

        /// Maximum object size in bytes.
        var maxObjectSizeInBytes: Int {
            return maxObjectSizeInMBs * 1024 * 1024
        }

        /// Memory cache capacity in bytes.
        var memoryCacheCapacityInBytes: Int {
            return memoryCacheCapacityInMBs * 1024 * 1024
        }

        /// Disk cache capacity in bytes.
        var diskCacheCapacityInBytes: Int {
            return diskCacheCapacityInMBs * 1024 * 1024
        }
    }
}
