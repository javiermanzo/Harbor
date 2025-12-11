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
    
    func testDataIsPersistedAsTwoFiles() async throws {
        let testData = "Disk Persistence Test".data(using: .utf8)!
        let request = TestDiskRequest(url: "https://disk.test/1")
        
        // 1. Store Data
        await HCache.Manager.shared.storeData(testData, for: request, response: nil)
        
        // 2. Wait for background disk write
        HCache.Manager.shared.diskQueue.sync {}
        
        // 3. Verify Files Exist
        guard let key = request.cacheKey else { return XCTFail() }
        let hash = key.sha256Hash
        let cacheDir = HCache.Manager.shared.cacheDirectory
        
        let dataURL = cacheDir.appendingPathComponent(hash)
        let metaURL = dataURL.appendingPathExtension("meta")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataURL.path), "Data file should exist on disk")
        XCTAssertTrue(FileManager.default.fileExists(atPath: metaURL.path), "Meta file should exist on disk")
        
        // 4. Verify Content
        let savedData = try Data(contentsOf: dataURL)
        XCTAssertEqual(savedData, testData, "Saved data on disk should match original")
    }
    
    func testLazyLoadingFromDisk() async throws {
        // Encode the string as a JSON value so JSONDecoder can read it back
        let rawString = "Lazy Load Test"
        let testData = try JSONEncoder().encode(rawString)
        
        let request = TestDiskRequest(url: "https://disk.test/lazy")
        
        // 1. Manually write files to disk (simulating previous session)
        guard let key = request.cacheKey else { return XCTFail() }
        let hash = key.sha256Hash
        let cacheDir = HCache.Manager.shared.cacheDirectory
        let dataURL = cacheDir.appendingPathComponent(hash)
        let metaURL = dataURL.appendingPathExtension("meta")
        
        // Create metadata
        // Note: Using a structure compatible with internal CacheMetadata
        struct TestMetadata: Encodable {
            let timestamp: Date
            let expirationTime: TimeInterval?
            let dataSize: Int
        }
        let meta = TestMetadata(timestamp: Date(), expirationTime: .oneHour, dataSize: testData.count)
        
        try testData.write(to: dataURL)
        try JSONEncoder().encode(meta).write(to: metaURL)
        
        // 2. Try to get data (should hit disk)
        let cached: TestDiskModel? = await HCache.Manager.shared.getCachedData(for: request)
        
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.value, "Lazy Load Test")
    }
    
    func testCorruptedMetaFileIsIgnored() async throws {
        let testData = "Corrupt Test".data(using: .utf8)!
        let request = TestDiskRequest(url: "https://disk.test/corrupt")
        
        guard let key = request.cacheKey else { return XCTFail() }
        let hash = key.sha256Hash
        let cacheDir = HCache.Manager.shared.cacheDirectory
        let dataURL = cacheDir.appendingPathComponent(hash)
        let metaURL = dataURL.appendingPathExtension("meta")
        
        // 1. Write valid data but corrupt metadata (garbage json)
        try testData.write(to: dataURL)
        try "Not A JSON".data(using: .utf8)!.write(to: metaURL)
        
        // 2. Try to get data
        let cached: TestDiskModel? = await HCache.Manager.shared.getCachedData(for: request)
        
        // 3. Should fail gracefully (return nil)
        XCTAssertNil(cached, "Should return nil if metadata is corrupted")
    }
    
    func testLargeFileLimit() async {
        // 1. Create data > 50MB (Limit set in Manager)
        let largeData = Data(count: 51 * 1024 * 1024) 
        let request = TestDiskRequest(url: "https://disk.test/large")
        
        // 2. Try store
        await HCache.Manager.shared.storeData(largeData, for: request, response: nil)
        HCache.Manager.shared.diskQueue.sync {}
        
        // 3. Verify NOT in disk
        guard let key = request.cacheKey else { return }
        let hash = key.sha256Hash
        let dataURL = HCache.Manager.shared.cacheDirectory.appendingPathComponent(hash)
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataURL.path), "Should not persist files larger than limit")
    }
}

// MARK: - Helpers

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
    let cacheConfiguration: HCache.Configuration? = .enabled()
}

