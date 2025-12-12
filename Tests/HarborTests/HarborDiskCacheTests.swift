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
        Harbor.clearAllCache()
        // Ensure disk operations finish
        HCache.Manager.shared.diskQueue.sync {}
    }
    
    override func tearDown() async throws {
        Harbor.clearAllCache()
        HCache.Manager.shared.diskQueue.sync {}
    }
    
    // MARK: - Physical Persistence Tests
    
    func testDataIsPersistedAsSingleFile() async throws {
        let testData = "Disk Persistence Test".data(using: .utf8)!
        let request = TestDiskRequest(url: "https://disk.test/1")
        
        // 1. Store Data
        await HCache.Manager.shared.storeData(testData, for: request, response: nil)
        
        // 2. Wait for background disk write
        HCache.Manager.shared.diskQueue.sync {}
        
        // 3. Verify File Exists
        guard let key = request.cacheKey else { return XCTFail() }
        let hash = key.sha256Hash
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
        
        // 1. Manually write file to disk (simulating previous session)
        guard let key = request.cacheKey else { return XCTFail() }
        let hash = key.sha256Hash
        let cacheDir = HCache.Manager.shared.cacheDirectory
        let fileURL = cacheDir.appendingPathComponent(hash).appendingPathExtension("cache")
        
        // Create DiskEntry manually
        let entry = TestDiskEntry(data: testData, timestamp: Date(), expirationTime: .oneHour)
        let encodedEntry = try JSONEncoder().encode(entry)
        
        try encodedEntry.write(to: fileURL)
        
        // 2. Try to get data (should hit disk)
        let cached: TestDiskModel? = await HCache.Manager.shared.getCachedData(for: request)
        
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.value, "Lazy Load Test")
    }
    
    func testCorruptedCacheFileIsIgnored() async throws {
        let request = TestDiskRequest(url: "https://disk.test/corrupt")
        
        guard let key = request.cacheKey else { return XCTFail() }
        let hash = key.sha256Hash
        let cacheDir = HCache.Manager.shared.cacheDirectory
        let fileURL = cacheDir.appendingPathComponent(hash).appendingPathExtension("cache")
        
        // 1. Write garbage data to file
        try "Not A Valid DiskEntry JSON".data(using: .utf8)!.write(to: fileURL)
        
        // 2. Try to get data
        let cached: TestDiskModel? = await HCache.Manager.shared.getCachedData(for: request)
        
        // 3. Should fail gracefully (return nil)
        XCTAssertNil(cached, "Should return nil if cache file is corrupted")
    }
    
    func testLargeFileLimit() async {
        // 1. Create data > 10MB (Default Limit set in Manager)
        let largeData = Data(count: 11 * 1024 * 1024)
        let request = TestDiskRequest(url: "https://disk.test/large")
        
        // 2. Try store
        await HCache.Manager.shared.storeData(largeData, for: request, response: nil)
        HCache.Manager.shared.diskQueue.sync {}
        
        // 3. Verify NOT in disk
        guard let key = request.cacheKey else { return }
        let hash = key.sha256Hash
        let fileURL = HCache.Manager.shared.cacheDirectory.appendingPathComponent(hash).appendingPathExtension("cache")
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "Should not persist files larger than limit")
    }

    func testCustomLargeFileLimit() async {
        // 1. Create data > 10MB but < 20MB
        let largeData = Data(count: 15 * 1024 * 1024)
        var request = TestDiskRequest(url: "https://disk.test/large-custom")
        request.cacheConfiguration = .enabled(maxObjectSizeInMBs: 20)
        
        // 2. Try store
        await HCache.Manager.shared.storeData(largeData, for: request, response: nil)
        HCache.Manager.shared.diskQueue.sync {}
        
        // 3. Verify IS in disk
        guard let key = request.cacheKey else { return }
        let hash = key.sha256Hash
        let fileURL = HCache.Manager.shared.cacheDirectory.appendingPathComponent(hash).appendingPathExtension("cache")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Should persist files smaller than custom limit")
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
    var cacheConfiguration: HCache.Configuration? = .enabled()
}
