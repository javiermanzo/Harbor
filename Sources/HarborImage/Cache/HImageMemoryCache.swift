//
//  HImageMemoryCache.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation
import HarborCore
#if canImport(UIKit)
import UIKit
#endif

/// The decoded images in memory, readable synchronously from any thread so `HImageView` can
/// show a cached image in its first render, without a placeholder. An entry costs its decoded
/// bytes (`bytesPerRow × height`, times the frames an animation keeps decoded); the system may
/// evict entries under memory pressure, and on UIKit platforms every entry is dropped on a
/// memory warning. Entries do not expire.
///
/// The cache also remembers which entries belong to each original image, so storing or removing
/// an image drops every size and processing of it.
final class HImageMemoryCache: Sendable {
    /// The shared memory cache.
    static let shared = HImageMemoryCache()

    /// The storage. `NSCache` is thread-safe, which the SDK does not express as `Sendable`.
    private let storage: HNSCacheBox
    /// The memory keys of each original key, kept in sync with the evictions of `storage`.
    private let keysByOriginal: HLockedState<[String: Set<String>]>

    /// Creates a memory cache with the default capacity.
    private init() {
        let keysByOriginal = HLockedState([String: Set<String>]())
        let cache = NSCache<NSString, HImageMemoryEntry>()
        cache.totalCostLimit = HImageCache.Configuration().memoryCapacityInBytes
        let observer = HEvictionObserver(keysByOriginal: keysByOriginal)
        cache.delegate = observer
        self.keysByOriginal = keysByOriginal
        self.storage = HNSCacheBox(cache: cache, observer: observer)
        #if canImport(UIKit) && !os(watchOS)
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [storage] _ in
            storage.cache.removeAllObjects()
        }
        #endif
    }
}

// MARK: - Access

extension HImageMemoryCache {
    /// The cached image for the key.
    /// - Parameter key: The memory key.
    func result(forKey key: String) -> HImageResult? {
        storage.cache.object(forKey: key as NSString)?.result
    }

    /// Caches an image.
    /// - Parameters:
    ///   - result: The image.
    ///   - key: The memory key.
    ///   - originalKey: The original cache key the image belongs to.
    func store(_ result: HImageResult, forKey key: String, originalKey: String) {
        let entry = HImageMemoryEntry(result: result, key: key, originalKey: originalKey)
        storage.cache.setObject(entry, forKey: key as NSString, cost: Self.cost(of: result))
        // After the write: replacing an entry reports the old one as evicted, under the same key.
        keysByOriginal.withLock { _ = $0[originalKey, default: []].insert(key) }
    }

    /// Removes every image of an original key: all its sizes and processings.
    /// - Parameter originalKey: The original cache key.
    func removeImage(originalKey: String) {
        // Taken out of the lock first: removing an object calls the eviction observer, which locks too.
        let keys = keysByOriginal.withLock { $0.removeValue(forKey: originalKey) } ?? []
        for key in keys {
            storage.cache.removeObject(forKey: key as NSString)
        }
    }

    /// Removes every image.
    func removeAll() {
        storage.cache.removeAllObjects()
        keysByOriginal.withLock { $0.removeAll() }
    }

    /// Sets the capacity in bytes.
    /// - Parameter bytes: The capacity.
    func setCapacity(_ bytes: Int) {
        storage.cache.totalCostLimit = bytes
    }

    /// The memory an image takes: its decoded bytes, times the frames an animation keeps decoded
    /// at most (`HImageAnimation.maxCachedFrames`).
    /// - Parameter result: The image.
    private static func cost(of result: HImageResult) -> Int {
        let frameBytes = result.image.bytesPerRow * result.image.height
        guard let animation = result.animation else { return frameBytes }
        return frameBytes * min(animation.frameCount, HImageAnimation.maxCachedFrames)
    }
}

// MARK: - Entry

/// A cached image, boxed for `NSCache`, with the keys it is stored under.
final class HImageMemoryEntry: Sendable {
    /// The image.
    let result: HImageResult
    /// The memory key.
    let key: String
    /// The original cache key the image belongs to.
    let originalKey: String

    /// Boxes an image.
    /// - Parameters:
    ///   - result: The image.
    ///   - key: The memory key.
    ///   - originalKey: The original cache key.
    init(result: HImageResult, key: String, originalKey: String) {
        self.result = result
        self.key = key
        self.originalKey = originalKey
    }
}

// MARK: - Eviction Observer

/// Removes an entry from the index of keys when `NSCache` evicts or removes it.
private final class HEvictionObserver: NSObject, NSCacheDelegate, Sendable {
    /// The memory keys of each original key.
    private let keysByOriginal: HLockedState<[String: Set<String>]>

    /// Creates the observer.
    /// - Parameter keysByOriginal: The index it keeps in sync.
    init(keysByOriginal: HLockedState<[String: Set<String>]>) {
        self.keysByOriginal = keysByOriginal
    }

    /// Drops the evicted entry from the index.
    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject object: Any) {
        guard let entry = object as? HImageMemoryEntry else { return }
        keysByOriginal.withLock { index in
            index[entry.originalKey]?.remove(entry.key)
            if index[entry.originalKey]?.isEmpty == true {
                index[entry.originalKey] = nil
            }
        }
    }
}

// MARK: - Storage Box

/// Holds the `NSCache`, which Apple documents as thread-safe, and its delegate (`NSCache` keeps
/// its delegate weakly).
private struct HNSCacheBox: @unchecked Sendable {
    /// The cache.
    let cache: NSCache<NSString, HImageMemoryEntry>
    /// The eviction observer, retained here.
    let observer: HEvictionObserver
}
