//
//  HarborStreamTests.swift
//  Harbor
//
//  Created by Javier Manzo on 20/07/2025.
//

import XCTest
@testable import Harbor

final class HarborStreamTests: XCTestCase {
    
    override func setUp() async throws {
        // Clear all cache before each test
        await Harbor.clearAllCache()
        await Harbor.removeAllMocks()
        await Harbor.setMocksOnlyInDebug(false)
        // Set default cache to disabled (original behavior)
        await Harbor.setDefaultCacheConfiguration(.disabled)
    }
    
    override func tearDown() async throws {
        // Clear all cache after each test
        await Harbor.clearAllCache()
        await Harbor.removeAllMocks()
    }
    
    // MARK: - Request Stream Tests
    
    func testRequestStreamCacheOnly() async {
        let testData = TestStreamData(value: "stream-cache-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(request: TestStreamRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestStreamRequest()
        
        // First make a request to populate cache
        _ = await request.request()
        
        await Harbor.removeAllMocks() // Remove mock to ensure only cache is used
        
        // Test cache-only stream
        var results: [(TestStreamData, HOriginType)] = []
        do {
            for try await (response, origin) in request.requestStream(source: .cacheOnly) {
                results.append((response, origin))
            }
        } catch {
            XCTFail("Stream should not throw error when cache exists: \(error)")
        }
        
        XCTAssertEqual(results.count, 1, "Should get exactly one cache result")
        XCTAssertEqual(results.first?.0.value, "stream-cache-test")
        XCTAssertEqual(results.first?.1, .cache)
    }
    
    func testRequestStreamCacheOnlyNoCachedData() async {
        let request = TestStreamRequest()
        
        // Test cache-only stream with no cached data
        do {
            for try await _ in request.requestStream(source: .cacheOnly) {
                XCTFail("Should not yield any results when no cache exists")
            }
            XCTFail("Stream should throw noCachedDataFound error")
        } catch HRequestError.noCachedDataFound {
            // Expected error
        } catch {
            XCTFail("Should throw noCachedDataFound error, got: \(error)")
        }
    }
    
    func testRequestStreamRemoteOnly() async {
        let testData = TestStreamData(value: "stream-remote-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(request: TestStreamRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestStreamRequest()
        
        // Test remote-only stream
        var results: [(TestStreamData, HOriginType)] = []
        do {
            for try await (response, origin) in request.requestStream(source: .remoteOnly) {
                results.append((response, origin))
            }
        } catch {
            XCTFail("Stream should not throw error: \(error)")
        }
        
        XCTAssertEqual(results.count, 1, "Should get exactly one remote result")
        XCTAssertEqual(results.first?.0.value, "stream-remote-test")
        XCTAssertEqual(results.first?.1, .remote)
        
        await Harbor.removeAllMocks()
    }
    
    func testRequestStreamCacheAndRemote() async {
        let testData = TestStreamData(value: "stream-both-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(request: TestStreamRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestStreamRequest()
        
        // First populate cache
        _ = await request.request()
        
        // Test cache-and-remote stream
        var results: [(TestStreamData, HOriginType)] = []
        do {
            for try await (response, origin) in request.requestStream(source: .cacheAndRemote) {
                results.append((response, origin))
            }
        } catch {
            XCTFail("Stream should not throw error: \(error)")
        }
        
        XCTAssertEqual(results.count, 2, "Should get both cache and remote results")
        XCTAssertEqual(results[0].0.value, "stream-both-test")
        XCTAssertEqual(results[0].1, .cache, "First result should be from cache")
        XCTAssertEqual(results[1].0.value, "stream-both-test")
        XCTAssertEqual(results[1].1, .remote, "Second result should be from remote")
        
        await Harbor.removeAllMocks()
    }
    
    func testRequestStreamCacheAndRemoteNoCache() async {
        let testData = TestStreamData(value: "stream-no-cache-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(request: TestStreamRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestStreamRequest()
        
        // Test cache-and-remote stream with no cache
        var results: [(TestStreamData, HOriginType)] = []
        do {
            for try await (response, origin) in request.requestStream(source: .cacheAndRemote) {
                results.append((response, origin))
            }
        } catch {
            XCTFail("Stream should not throw error: \(error)")
        }
        
        XCTAssertEqual(results.count, 1, "Should get only remote result when no cache")
        XCTAssertEqual(results.first?.0.value, "stream-no-cache-test")
        XCTAssertEqual(results.first?.1, .remote)
        
        await Harbor.removeAllMocks()
    }
    
    func testRequestStreamDefaultSource() async {
        let testData = TestStreamData(value: "stream-default-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(request: TestStreamRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestStreamRequest()
        
        // Test default source (should be .cacheAndRemote)
        var results: [(TestStreamData, HOriginType)] = []
        do {
            for try await (response, origin) in request.requestStream() {
                results.append((response, origin))
            }
        } catch {
            XCTFail("Stream should not throw error: \(error)")
        }
        
        // Should get only remote since no cache exists
        XCTAssertEqual(results.count, 1, "Should get only remote result when no cache and using default source")
        XCTAssertEqual(results.first?.0.value, "stream-default-test")
        XCTAssertEqual(results.first?.1, .remote)
        
        await Harbor.removeAllMocks()
    }
    
    func testRequestStreamNetworkError() async {
        let request = TestStreamRequest()
        
        // No mock registered, should get network error for remote-only
        do {
            for try await _ in request.requestStream(source: .remoteOnly) {
                XCTFail("Should not yield any results when network fails")
            }
            XCTFail("Stream should throw network error")
        } catch {
            // Expected error (should be a network-related error)
            XCTAssertTrue(error is HRequestError, "Should throw HRequestError")
        }
    }
    
    func testRequestStreamCacheAndRemoteWithNetworkError() async {
        let testData = TestStreamData(value: "stream-cache-with-error-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(request: TestStreamRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestStreamRequest()
        
        // First populate cache
        _ = await request.request()
        
        // Remove mock to simulate network error
        await Harbor.removeAllMocks()
        
        // Test cache-and-remote stream with network error
        var results: [(TestStreamData, HOriginType)] = []
        do {
            for try await (response, origin) in request.requestStream(source: .cacheAndRemote) {
                results.append((response, origin))
            }
            XCTFail("Stream should throw error when remote fails")
        } catch {
             // Expected error
        }
        
        // Should get only cache result since network fails
        XCTAssertEqual(results.count, 1, "Should get only cache result when network fails")
        XCTAssertEqual(results.first?.0.value, "stream-cache-with-error-test")
        XCTAssertEqual(results.first?.1, .cache)
    }
}

// MARK: - Test Models and Requests

private struct TestStreamData: HModel {
    let value: String
    let timestamp: Date
}

private struct TestStreamRequest: HGetRequestProtocol {
    typealias Model = TestStreamData
    
    let url: String = "https://stream.example.com/test"
    let cacheConfiguration: HCache.Configuration? = HCache.Configuration()
}
