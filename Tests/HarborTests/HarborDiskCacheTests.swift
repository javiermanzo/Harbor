//
//  HarborDiskCacheTests.swift
//  Harbor
//
//  Created by Javier Manzo on 11/07/2025.
//

import XCTest
@testable import Harbor

@HRequestManagerActor
final class HarborDiskCacheTests: XCTestCase {

    override func setUp() async throws {
        await Harbor.clearAllCache()
        await HCache.Manager.shared.waitForPendingDiskOperations()
    }

    override func tearDown() async throws {
        await Harbor.clearAllCache()
        await HCache.Manager.shared.waitForPendingDiskOperations()
    }

    // MARK: - Physical Persistence Tests

    func testDataIsPersistedAsSingleFile() async throws {
        let testData = "Disk Persistence Test".data(using: .utf8)!
        let request = TestDiskRequest(url: "https://disk.test/1")
        let config = HCache.Configuration()

        // 1. Store Data - use URL directly as cache key
        let key = request.url
        await HCache.Manager.shared.storeData(testData, forKey: key, config: config, response: nil)

        // 2. Wait for background disk write
        await HCache.Manager.shared.waitForPendingDiskOperations()

        // 3. Verify File Exists
        let hash = key.sha256Hex
        let cacheDir = HCache.Manager.shared.cacheDirectory

        // New format: .cache extension
        let fileURL = cacheDir.appendingPathComponent(hash).appendingPathExtension("cache")

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Single cache file should exist on disk")

        // 4. Verify Content: magic + length-prefixed metadata header + raw body bytes
        let fileData = try Data(contentsOf: fileURL)
        XCTAssertEqual(fileData.prefix(4), Data("HRBC".utf8), "Entry files should start with the format signature")
        let (metadata, body) = try XCTUnwrap(HCache.DiskCodec.decode(fileData))
        XCTAssertEqual(body, testData, "Saved body should match the original")
        XCTAssertEqual(metadata.version, HCache.EntryMetadata.currentVersion)
        XCTAssertTrue(fileData.suffix(testData.count) == testData, "The body should be stored raw, not base64 encoded")
    }

    func testLazyLoadingFromDisk() async throws {
        // Encode the string as a JSON value so JSONDecoder can read it back
        let rawString = "Lazy Load Test"
        let testData = try JSONEncoder().encode(rawString)

        let request = TestDiskRequest(url: "https://disk.test/lazy")
        let config = HCache.Configuration()

        // 1. Manually write file to disk (simulating previous session) - use URL directly as key
        let key = request.url
        let hash = key.sha256Hex
        let cacheDir = HCache.Manager.shared.cacheDirectory
        let fileURL = cacheDir.appendingPathComponent(hash).appendingPathExtension("cache")

        // Create the entry file manually
        let metadata = HCache.EntryMetadata(timestamp: Date(), expirationTime: .oneHour)
        try HCache.DiskCodec.encode(metadata, body: testData).write(to: fileURL)

        // 2. Try to get data (should hit disk)
        let cached: TestDiskModel? = await HCache.Manager.shared.getCachedData(forKey: key, type: TestDiskModel.self, config: config)

        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.value, "Lazy Load Test")
    }

    func testCorruptedCacheFileIsIgnored() async throws {
        let request = TestDiskRequest(url: "https://disk.test/corrupt")
        let config = HCache.Configuration()

        let key = request.url
        let hash = key.sha256Hex
        let cacheDir = HCache.Manager.shared.cacheDirectory
        let fileURL = cacheDir.appendingPathComponent(hash).appendingPathExtension("cache")

        // 1. Write garbage data to file
        try "Not A Valid DiskEntry JSON".data(using: .utf8)!.write(to: fileURL)

        // 2. Try to get data
        let cached: TestDiskModel? = await HCache.Manager.shared.getCachedData(forKey: key, type: TestDiskModel.self, config: config)

        // 3. Should fail gracefully (return nil)
        XCTAssertNil(cached, "Should return nil if cache file is corrupted")
    }

    func testLargeFileLimit() async {
        // 1. Create data > 10MB (Default Limit set in Manager)
        let largeData = Data(count: 11 * 1024 * 1024)
        let request = TestDiskRequest(url: "https://disk.test/large")
        let config = HCache.Configuration()

        // 2. Try store - use URL directly as key
        let key = request.url
        await HCache.Manager.shared.storeData(largeData, forKey: key, config: config, response: nil)
        await HCache.Manager.shared.waitForPendingDiskOperations()

        // 3. Verify NOT in disk
        let hash = key.sha256Hex
        let fileURL = HCache.Manager.shared.cacheDirectory.appendingPathComponent(hash).appendingPathExtension("cache")

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "Should not persist files larger than limit")
    }

    func testCustomLargeFileLimit() async {
        // 1. Create data > 10MB but < 20MB
        let largeData = Data(count: 15 * 1024 * 1024)
        let request = TestDiskRequest(url: "https://disk.test/large-custom")
        let config = HCache.Configuration(maxObjectSizeInMBs: 20)

        // 2. Try store - use URL directly as key
        let key = request.url
        await HCache.Manager.shared.storeData(largeData, forKey: key, config: config, response: nil)
        await HCache.Manager.shared.waitForPendingDiskOperations()

        // 3. Verify IS in disk
        let hash = key.sha256Hex
        let fileURL = HCache.Manager.shared.cacheDirectory.appendingPathComponent(hash).appendingPathExtension("cache")

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Should persist files smaller than custom limit")
    }

    // MARK: - Disk Capacity Tests

    func testDiskCapacityEvictsLeastRecentlyUsedEntries() async {
        // Bodies are stored raw, so each 900 KB payload takes ~900 KB on disk:
        // three fit the 3 MB capacity, a fourth does not.
        let config = HCache.Configuration(diskCacheCapacityInMBs: 3)
        let entryData = try! JSONEncoder().encode(String(repeating: "a", count: 900 * 1024))

        let keys = [
            "https://disk.test/lru-first",
            "https://disk.test/lru-second",
            "https://disk.test/lru-third"
        ]
        for key in keys {
            await HCache.Manager.shared.storeData(entryData, forKey: key, config: config, response: nil)
        }

        // Reading the oldest entry makes it the most recently used one
        let read: String? = await HCache.Manager.shared.getCachedData(forKey: keys[0], type: String.self, config: config)
        XCTAssertNotNil(read)

        // The extra entry pushes the directory over the 3 MB capacity
        let extraKey = "https://disk.test/lru-extra"
        await HCache.Manager.shared.storeData(entryData, forKey: extraKey, config: config, response: nil)
        await HCache.Manager.shared.waitForPendingDiskOperations()

        XCTAssertTrue(fileExists(for: keys[0]), "A recently read entry should be kept (LRU, not FIFO)")
        XCTAssertFalse(fileExists(for: keys[1]), "The least recently used entry should be evicted")
        XCTAssertTrue(fileExists(for: keys[2]), "More recent entries should be kept")
        XCTAssertTrue(fileExists(for: extraKey), "The entry that triggered the eviction should never be evicted itself")
    }

    func testDiskCapacityIsEnforcedAcrossManyWrites() async throws {
        // Given a 1 MB capacity and 300 KB entries
        let config = HCache.Configuration(diskCacheCapacityInMBs: 1)
        let entryData = Data(count: 300 * 1024)

        // When many entries are written
        for index in 0 ..< 10 {
            await HCache.Manager.shared.storeData(entryData, forKey: "https://disk.test/capacity-\(index)", config: config, response: nil)
        }
        await HCache.Manager.shared.waitForPendingDiskOperations()

        // Then the directory never exceeds the capacity and the index matches the files on disk
        let files = try FileManager.default.contentsOfDirectory(at: HCache.Manager.shared.cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
        let total = try files.reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThanOrEqual(total, config.diskCacheCapacityInBytes)
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(HCache.Manager.shared.diskIndexTotalSize, total)
        XCTAssertTrue(fileExists(for: "https://disk.test/capacity-9"), "The newest entry should be kept")
        XCTAssertFalse(fileExists(for: "https://disk.test/capacity-0"), "The oldest entry should be evicted")
    }

    // MARK: - Format Tests

    func testOldVersionFileIsDiscardedOnRead() async throws {
        // Given a file in the previous (v1, JSON + base64) format
        let key = "https://disk.test/old-version"
        let fileURL = fileURL(for: key)
        let legacyEntry = TestDiskEntry(data: try JSONEncoder().encode("old"), timestamp: Date(), expirationTime: .oneHour)
        try JSONEncoder().encode(legacyEntry).write(to: fileURL)

        // When it is read
        let cached: String? = await HCache.Manager.shared.getCachedData(forKey: key, type: String.self, config: HCache.Configuration())

        // Then it is a miss and the file is deleted
        XCTAssertNil(cached)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "Files in an outdated format should be discarded")
    }

    func testFileWithAnotherMetadataVersionIsRejected() async throws {
        var metadata = HCache.EntryMetadata(timestamp: Date(), expirationTime: .oneHour)
        metadata.version = HCache.EntryMetadata.currentVersion + 1
        let fileData = try HCache.DiskCodec.encode(metadata, body: Data("{}".utf8))

        XCTAssertNil(HCache.DiskCodec.decode(fileData))
    }

    func testStartupCleanupDiscardsOutdatedAndExpiredFilesOnly() async throws {
        // Given an outdated file, an expired entry without validators, an expired entry with
        // a validator and a fresh entry
        let outdatedKey = "https://disk.test/startup-outdated"
        try JSONEncoder().encode(TestDiskEntry(data: Data(), timestamp: Date(), expirationTime: nil)).write(to: fileURL(for: outdatedKey))

        let expiredKey = "https://disk.test/startup-expired"
        let expired = HCache.EntryMetadata(timestamp: Date().addingTimeInterval(-120), expirationTime: 60)
        try HCache.DiskCodec.encode(expired, body: Data()).write(to: fileURL(for: expiredKey))

        let revalidatableKey = "https://disk.test/startup-revalidatable"
        var revalidatable = expired
        revalidatable.etag = "\"v1\""
        try HCache.DiskCodec.encode(revalidatable, body: Data()).write(to: fileURL(for: revalidatableKey))

        let freshKey = "https://disk.test/startup-fresh"
        try HCache.DiskCodec.encode(HCache.EntryMetadata(timestamp: Date(), expirationTime: 60), body: Data()).write(to: fileURL(for: freshKey))

        // When the startup cleanup runs
        await HCache.Manager.shared.runStartupCleanup()

        // Then
        XCTAssertFalse(fileExists(for: outdatedKey))
        XCTAssertFalse(fileExists(for: expiredKey))
        XCTAssertTrue(fileExists(for: revalidatableKey), "Expired entries with validators can still be revalidated")
        XCTAssertTrue(fileExists(for: freshKey))
    }

    func testValidatorsAreReadFromTheMetadataHeaderOnly() async throws {
        // Given an entry file whose body is truncated garbage but whose header is intact
        let key = "https://disk.test/header-only"
        var metadata = HCache.EntryMetadata(timestamp: Date(), expirationTime: .oneHour)
        metadata.etag = "\"header-etag\""
        var fileData = try HCache.DiskCodec.encode(metadata, body: Data())
        fileData.append(Data(repeating: 0xFF, count: 16))
        try fileData.write(to: fileURL(for: key))

        // When only the validators are requested, the header alone answers
        let etag = await HCache.Manager.shared.getETag(forKey: key)
        let validators = await HCache.Manager.shared.getValidators(forKey: key)

        XCTAssertEqual(etag, "\"header-etag\"")
        XCTAssertEqual(validators.etag, "\"header-etag\"")
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentStoreAndRead() async throws {
        let config = HCache.Configuration()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    let key = "https://disk.test/concurrent-\(index)"
                    let data = try! JSONEncoder().encode("value-\(index)")
                    await HCache.Manager.shared.storeData(data, forKey: key, config: config, response: nil)
                    _ = await HCache.Manager.shared.getCachedData(forKey: key, type: String.self, config: config)
                }
            }
            try await group.waitForAll()
        }
        await HCache.Manager.shared.waitForPendingDiskOperations()

        for index in 0..<20 {
            let key = "https://disk.test/concurrent-\(index)"
            let cached: String? = await HCache.Manager.shared.getCachedData(forKey: key, type: String.self, config: config)
            XCTAssertEqual(cached, "value-\(index)", "Every concurrently stored entry should be readable")
        }
    }

    // MARK: - Legacy Format Migration Tests

    func testLegacyFilesAreRemovedOnStore() async throws {
        let key = "https://disk.test/legacy"
        let hash = key.sha256Hex
        let cacheDir = HCache.Manager.shared.cacheDirectory

        // Legacy format: data file without extension plus a .meta sidecar
        let legacyDataURL = cacheDir.appendingPathComponent(hash)
        let legacyMetaURL = legacyDataURL.appendingPathExtension("meta")

        try "legacy data".data(using: .utf8)!.write(to: legacyDataURL)
        try "legacy meta".data(using: .utf8)!.write(to: legacyMetaURL)

        // Storing for the same key cleans up the legacy pair
        let testData = "current data".data(using: .utf8)!
        await HCache.Manager.shared.storeData(testData, forKey: key, config: HCache.Configuration(), response: nil)
        await HCache.Manager.shared.waitForPendingDiskOperations()

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDataURL.path), "Legacy data file should be removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyMetaURL.path), "Legacy meta file should be removed")

        let currentURL = legacyDataURL.appendingPathExtension("cache")
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentURL.path), "Current format file should exist")
    }

    // MARK: - Clear Cache Tests

    func testClearAllCacheRecreatesDirectory() async throws {
        let cacheDir = HCache.Manager.shared.cacheDirectory

        // Populate the directory
        let testData = "to be cleared".data(using: .utf8)!
        await HCache.Manager.shared.storeData(testData, forKey: "https://disk.test/clear", config: HCache.Configuration(), response: nil)
        await HCache.Manager.shared.waitForPendingDiskOperations()

        var isDirectory: ObjCBool = false
        let contentsBefore = try FileManager.default.contentsOfDirectory(atPath: cacheDir.path)
        XCTAssertFalse(contentsBefore.isEmpty, "Cache directory should contain entries before clearing")

        await HCache.Manager.shared.clearAllCache()

        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDir.path, isDirectory: &isDirectory), "Cache directory should exist after clearing")
        XCTAssertTrue(isDirectory.boolValue, "Cache directory should be a directory")

        let contentsAfter = try FileManager.default.contentsOfDirectory(atPath: cacheDir.path)
        XCTAssertTrue(contentsAfter.isEmpty, "Cache directory should be empty after clearing")
    }
}

// MARK: - Helpers

private extension HarborDiskCacheTests {
    func fileURL(for key: String) -> URL {
        HCache.Manager.shared.cacheDirectory.appendingPathComponent(key.sha256Hex).appendingPathExtension("cache")
    }

    func fileExists(for key: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: key).path)
    }

}

// Mirror of internal DiskEntry for testing

