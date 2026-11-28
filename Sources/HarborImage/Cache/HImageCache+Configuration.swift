//
//  HImageCache+Configuration.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

// MARK: - Configuration

public extension HImageCache {
    /// Sizes and lifetime of HarborImage's cache.
    struct Configuration: Sendable, Equatable {
        /// How long an entry on disk is served after it was stored, in seconds; a processed
        /// variant expires with the original it was rendered from. `nil` never expires. An
        /// expired entry is kept until it is replaced or evicted, and still served while the
        /// device is offline, with `.returnCacheDontLoad`, and when the download that should
        /// replace it fails for a transient reason (transport error, timeout, `5xx`). Memory
        /// entries do not expire.
        public let expirationTime: TimeInterval?
        /// Files larger than this (originals, processed variants or bytes given to
        /// `HarborImage.store(_:for:)`) are not written to disk, in megabytes.
        public let maxObjectSizeInMBs: Int
        /// Capacity of the memory cache in megabytes of decoded bytes (`bytesPerRow × height`,
        /// times the frames an animation keeps decoded).
        public let memoryCacheCapacityInMBs: Int
        /// Capacity of the disk cache in megabytes; past it the least recently used entries are evicted.
        public let diskCacheCapacityInMBs: Int
        /// Whether the original bytes are stored on disk too when the request has processors or
        /// an encoding, so another variant can be produced without downloading again.
        public let storesOriginalWhenProcessed: Bool
        /// The directory of the disk cache. `nil` (default) is `Caches/HarborImage`.
        public let directory: URL?

        /// Creates a configuration. Capacities are clamped to 1 MB and above.
        /// - Parameters:
        ///   - expirationTime: Lifetime of a disk entry in seconds, `nil` for none. Default: one week.
        ///   - maxObjectSizeInMBs: Largest file written to disk, in MB. Default: 20 MB.
        ///   - memoryCacheCapacityInMBs: Memory capacity in MB of decoded bytes. Default: 100 MB.
        ///   - diskCacheCapacityInMBs: Disk capacity in MB. Default: 300 MB.
        ///   - storesOriginalWhenProcessed: Whether the original is stored next to processed variants. Default: `false`.
        ///   - directory: The disk cache directory. Default: `nil`, `Caches/HarborImage`.
        public init(expirationTime: TimeInterval? = 7 * 24 * 60 * 60,
                    maxObjectSizeInMBs: Int = 20,
                    memoryCacheCapacityInMBs: Int = 100,
                    diskCacheCapacityInMBs: Int = 300,
                    storesOriginalWhenProcessed: Bool = false,
                    directory: URL? = nil) {
            self.expirationTime = expirationTime
            self.maxObjectSizeInMBs = Self.clamped(maxObjectSizeInMBs)
            self.memoryCacheCapacityInMBs = Self.clamped(memoryCacheCapacityInMBs)
            self.diskCacheCapacityInMBs = Self.clamped(diskCacheCapacityInMBs)
            self.storesOriginalWhenProcessed = storesOriginalWhenProcessed
            self.directory = directory
        }
    }
}

// MARK: - Bytes

extension HImageCache.Configuration {
    /// Largest download stored on disk, in bytes.
    var maxObjectSizeInBytes: Int { maxObjectSizeInMBs * 1024 * 1024 }
    /// Memory capacity in bytes.
    var memoryCapacityInBytes: Int { memoryCacheCapacityInMBs * 1024 * 1024 }
    /// Disk capacity in bytes.
    var diskCapacityInBytes: Int { diskCacheCapacityInMBs * 1024 * 1024 }

    /// The disk cache directory to use.
    var resolvedDirectory: URL {
        if let directory { return directory }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("HarborImage", isDirectory: true)
    }

    /// Clamps a capacity in megabytes to `1...(Int.max / 1 MB)`, so its size in bytes never overflows.
    /// - Parameter megabytes: The requested capacity.
    private static func clamped(_ megabytes: Int) -> Int {
        min(max(1, megabytes), Int.max / (1024 * 1024))
    }
}
