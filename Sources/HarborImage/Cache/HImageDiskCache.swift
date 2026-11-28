//
//  HImageDiskCache.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// The image bytes on disk: one file per key, named by SHA-256 digests (`HImageDiskKey`), in the
/// app's `Caches` directory (purgeable by the system and excluded from backups). The index
/// (size, storage date and last access of every file) is kept in memory, rebuilt from the file
/// attributes on first use; past the capacity the least recently used files are removed.
///
/// The index is isolated to `@HRequestManagerActor`; file reads and writes run off the actor.
@HRequestManagerActor
final class HImageDiskCache {
    /// The shared disk cache.
    static let shared = HImageDiskCache()

    /// What the index knows about a file.
    struct Entry {
        /// The file size in bytes.
        var size: Int
        /// When the file was written.
        var storedAt: Date
        /// When the file was last read or written.
        var lastAccess: Date
    }

    /// The directory the index describes; `nil` until first used.
    private var directory: URL?
    /// The files, by name.
    private var index: [String: Entry] = [:]
    /// The total size of the files, in bytes.
    private var totalSize = 0
    /// The index loading in progress, shared by the callers that need it.
    private var loading: Task<Void, Never>?
    /// Whether the index describes the files of `directory`.
    private var isLoaded = false
    /// Incremented by `removeAll(configuration:)`, so a load of the index that started before
    /// is discarded.
    private var indexGeneration = 0

    /// Creates the disk cache.
    private init() {}
}

// MARK: - Access

extension HImageDiskCache {
    /// Reads the bytes for the key. An expired entry is not deleted: it stays until a newer copy
    /// replaces it or the LRU evicts it, so it can still be served offline or when the download
    /// that should replace it fails.
    /// - Parameters:
    ///   - key: The disk key.
    ///   - configuration: The cache configuration (directory and expiration).
    ///   - allowsExpired: Whether an expired entry is returned.
    /// - Returns: The bytes, or `nil` when there is no usable entry.
    func data(for key: HImageDiskKey, configuration: HImageCache.Configuration, allowsExpired: Bool) async -> Data? {
        await prepare(configuration)
        guard let entry = index[key.fileName], let directory else { return nil }
        if !allowsExpired, Self.isExpired(entry, configuration: configuration) {
            return nil
        }
        guard let data = await Self.readFile(at: directory.appendingPathComponent(key.fileName)) else {
            // Purged by the system meanwhile.
            removeEntry(key.fileName)
            return nil
        }
        index[key.fileName]?.lastAccess = Date()
        return data
    }

    /// When the entry for the key was stored, or `nil` when there is none.
    /// - Parameters:
    ///   - key: The disk key.
    ///   - configuration: The cache configuration (directory).
    func storedAt(for key: HImageDiskKey, configuration: HImageCache.Configuration) async -> Date? {
        await prepare(configuration)
        return index[key.fileName]?.storedAt
    }

    /// Writes the bytes for the key, replacing any previous entry, and evicts the least recently
    /// used files past the capacity. Files larger than `maxObjectSizeInMBs` are not written.
    /// - Parameters:
    ///   - data: The bytes.
    ///   - key: The disk key.
    ///   - storedAt: The storage date that drives expiration. Default: `nil`, now. A variant
    ///     rendered from a cached original passes the original's date, so it expires with it.
    ///   - configuration: The cache configuration (directory and capacity).
    ///   - isCurrent: Checked before and after the write; when it is `false` (the cache was
    ///     cleared, the auth provider replaced, or the image stored or removed meanwhile) nothing
    ///     is kept.
    /// - Returns: Whether the bytes were stored.
    @discardableResult
    func store(_ data: Data, for key: HImageDiskKey, storedAt: Date? = nil, configuration: HImageCache.Configuration, isCurrent: () -> Bool) async -> Bool {
        guard data.count <= configuration.maxObjectSizeInBytes, data.count <= configuration.diskCapacityInBytes else { return false }
        await prepare(configuration)
        guard isCurrent(), let directory else { return false }

        let fileURL = directory.appendingPathComponent(key.fileName)
        let date = storedAt ?? Date()
        guard await Self.writeFile(data, to: fileURL, directory: directory, storedAt: date) else { return false }
        guard isCurrent(), directory == self.directory else {
            await Self.deleteFile(at: fileURL)
            return false
        }

        removeEntry(key.fileName)
        index[key.fileName] = Entry(size: data.count, storedAt: date, lastAccess: Date())
        totalSize += data.count
        await evict(capacity: configuration.diskCapacityInBytes, directory: directory)
        return true
    }

    /// Removes the original bytes of an image and every processed variant of it.
    /// - Parameters:
    ///   - originalKey: The original cache key (URL or `cacheKey`).
    ///   - configuration: The cache configuration (directory).
    func removeImage(originalKey: String, configuration: HImageCache.Configuration) async {
        await prepare(configuration)
        guard let directory else { return }
        let original = HImageDiskKey.original(originalKey)
        let variantPrefix = HImageDiskKey.variantPrefix(of: originalKey)
        let names = index.keys.filter { $0 == original.fileName || $0.hasPrefix(variantPrefix) }
        for name in names {
            removeEntry(name)
            await Self.deleteFile(at: directory.appendingPathComponent(name))
        }
    }

    /// Removes the entry for the key.
    /// - Parameters:
    ///   - key: The disk key.
    ///   - configuration: The cache configuration (directory).
    func remove(_ key: HImageDiskKey, configuration: HImageCache.Configuration) async {
        await prepare(configuration)
        guard let directory else { return }
        removeEntry(key.fileName)
        await Self.deleteFile(at: directory.appendingPathComponent(key.fileName))
    }

    /// Removes every file.
    /// - Parameter configuration: The cache configuration (directory).
    func removeAll(configuration: HImageCache.Configuration) async {
        let target = configuration.resolvedDirectory
        indexGeneration &+= 1
        loading = nil
        index.removeAll()
        totalSize = 0
        directory = target
        isLoaded = true
        await Self.resetDirectory(target)
    }

    /// The total size of the files, in bytes.
    /// - Parameter configuration: The cache configuration (directory).
    func size(configuration: HImageCache.Configuration) async -> Int {
        await prepare(configuration)
        return totalSize
    }

    /// The number of files.
    /// - Parameter configuration: The cache configuration (directory).
    func count(configuration: HImageCache.Configuration) async -> Int {
        await prepare(configuration)
        return index.count
    }

    /// Whether an entry is older than the configuration's expiration time.
    /// - Parameters:
    ///   - entry: The entry.
    ///   - configuration: The cache configuration.
    private static func isExpired(_ entry: Entry, configuration: HImageCache.Configuration) -> Bool {
        configuration.expirationTime.map { Date().timeIntervalSince(entry.storedAt) > $0 } ?? false
    }
}

// MARK: - Index

extension HImageDiskCache {
    /// Loads the index of the configured directory, once; a directory change reloads it.
    /// - Parameter configuration: The cache configuration.
    private func prepare(_ configuration: HImageCache.Configuration) async {
        let target = configuration.resolvedDirectory
        if directory != target {
            directory = target
            index.removeAll()
            totalSize = 0
            loading = nil
            isLoaded = false
            indexGeneration &+= 1
        }
        guard !isLoaded else { return }
        if let loading {
            await loading.value
            return
        }

        let generation = indexGeneration
        let task = Task {
            let files = await Self.listFiles(in: target)
            guard generation == indexGeneration, directory == target else { return }
            for file in files where index[file.name] == nil {
                index[file.name] = file.entry
                totalSize += file.entry.size
            }
            isLoaded = true
        }
        loading = task
        await task.value
    }

    /// Removes an entry from the index.
    /// - Parameter name: The file name.
    private func removeEntry(_ name: String) {
        if let entry = index.removeValue(forKey: name) {
            totalSize -= entry.size
        }
    }

    /// Removes the least recently used files until the total is at 90% of the capacity.
    /// - Parameters:
    ///   - capacity: The capacity in bytes.
    ///   - directory: The cache directory.
    private func evict(capacity: Int, directory: URL) async {
        guard totalSize > capacity else { return }
        let goal = capacity / 10 * 9
        var victims: [URL] = []
        for (name, _) in index.sorted(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            guard totalSize > goal else { break }
            removeEntry(name)
            victims.append(directory.appendingPathComponent(name))
        }
        for victim in victims {
            await Self.deleteFile(at: victim)
        }
    }
}

// MARK: - File System

extension HImageDiskCache {
    /// A file found while loading the index.
    private struct ListedFile: Sendable {
        /// The file name.
        let name: String
        /// Its size and dates.
        let entry: Entry
    }

    /// Lists the cache files with their attributes, off the actor.
    /// - Parameter directory: The cache directory.
    nonisolated private static func listFiles(in directory: URL) async -> [ListedFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return []
        }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            let stored = values.creationDate ?? values.contentModificationDate ?? Date()
            let accessed = values.contentModificationDate ?? stored
            return ListedFile(name: url.lastPathComponent, entry: Entry(size: values.fileSize ?? 0, storedAt: stored, lastAccess: accessed))
        }
    }

    /// Reads a file and records the access as its modification date, off the actor.
    /// - Parameter url: The file.
    nonisolated private static func readFile(at url: URL) async -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    /// Writes a file atomically, creating the directory if needed, off the actor. The storage date
    /// is kept as the file's creation date, so the index rebuilt at the next launch finds it.
    /// - Parameters:
    ///   - data: The bytes.
    ///   - url: The file.
    ///   - directory: The cache directory.
    ///   - storedAt: The storage date.
    /// - Returns: Whether the file was written.
    nonisolated private static func writeFile(_ data: Data, to url: URL, directory: URL, storedAt: Date) async -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.creationDate: storedAt], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    /// Deletes a file, off the actor.
    /// - Parameter url: The file.
    nonisolated private static func deleteFile(at url: URL) async {
        try? FileManager.default.removeItem(at: url)
    }

    /// Deletes the directory and its files, off the actor.
    /// - Parameter directory: The cache directory.
    nonisolated private static func resetDirectory(_ directory: URL) async {
        try? FileManager.default.removeItem(at: directory)
    }
}
