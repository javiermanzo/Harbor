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

        // 4. Verify Content (It's a DiskEntry wrapper now)
        let fileData = try Data(contentsOf: fileURL)
        let diskEntry = try JSONDecoder().decode(TestDiskEntry.self, from: fileData)

        XCTAssertEqual(diskEntry.data, testData, "Saved data inside wrapper should match original")
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

        // Create DiskEntry manually
        let entry = TestDiskEntry(data: testData, timestamp: Date(), expirationTime: .oneHour)
        let encodedEntry = try JSONEncoder().encode(entry)

        try encodedEntry.write(to: fileURL)

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

    func testDiskCapacityEvictsOldestEntries() async {
        // Entries are stored JSON-encoded (base64 data), so each 600 KB payload takes ~800 KB on disk
        let config = HCache.Configuration(diskCacheCapacityInMBs: 3)
        let entryData = Data(count: 600 * 1024)

        let keys = [
            "https://disk.test/lru-oldest",
            "https://disk.test/lru-middle",
            "https://disk.test/lru-newest"
        ]

        // ~2.4 MB fits the 3 MB capacity, so nothing is evicted yet
        for key in keys {
            await HCache.Manager.shared.storeData(entryData, forKey: key, config: config, response: nil)
        }
        await HCache.Manager.shared.waitForPendingDiskOperations()

        // Pin deterministic modification dates instead of relying on write-order mtimes
        let cacheDir = HCache.Manager.shared.cacheDirectory
        let fileURLs = keys.map { cacheDir.appendingPathComponent($0.sha256Hex).appendingPathExtension("cache") }
        let sentinelDates = [
            Date().addingTimeInterval(-3600),
            Date().addingTimeInterval(-1800),
            Date().addingTimeInterval(-60)
        ]
        for (fileURL, date) in zip(fileURLs, sentinelDates) {
            try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: fileURL.path)
        }

        // The extra entry pushes the directory over the 3 MB capacity
        let extraKey = "https://disk.test/lru-extra"
        await HCache.Manager.shared.storeData(entryData, forKey: extraKey, config: config, response: nil)
        await HCache.Manager.shared.waitForPendingDiskOperations()

        let extraURL = cacheDir.appendingPathComponent(extraKey.sha256Hex).appendingPathExtension("cache")

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURLs[0].path), "Oldest entry should be evicted to fit the disk capacity")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURLs[1].path), "Middle entry should be kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURLs[2].path), "Newest entry should be kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extraURL.path), "The entry that triggered the eviction should never be evicted itself")
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

// Mirror of internal DiskEntry for testing
private struct TestDiskEntry: Codable {
    let data: Data
    let timestamp: Date
    let expirationTime: TimeInterval?
}

private struct TestDiskModel: HModel {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

private struct TestDiskRequest: HGetRequestProtocol {
    typealias Model = TestDiskModel
    let url: String
    let cacheType: HCache.CacheType = .custom(HCache.Configuration())
}
