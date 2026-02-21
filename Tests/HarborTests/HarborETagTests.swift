//
//  HarborETagTests.swift
//  Harbor
//
//  Tests for ETag and cache policy functionality
//

import XCTest
@testable import Harbor

final class HarborETagTests: XCTestCase {
    
    override func setUp() async throws {
        await Harbor.removeAllMocks()
        await Harbor.clearAllCache()
    }
    
    override func tearDown() async throws {
        await Harbor.removeAllMocks()
        await Harbor.clearAllCache()
    }
    
    // MARK: - Cache Policy Tests
    
    func testDefaultCachePolicyIsURLCache() async throws {
        let request = GetUsersRequest()
        XCTAssertEqual(request.cachePolicy, .urlCache(), "Default cache policy should be urlCache")
    }
    
    func testCustomCachePolicy() async throws {
        let request = GetUsersWithCustomCacheRequest()
        guard case .custom(let config) = request.cachePolicy else {
            XCTFail("Expected custom cache policy")
            return
        }
        XCTAssertEqual(config.expirationTime, .oneHour)
        XCTAssertEqual(config.maxObjectSizeInMBs, 10)
    }
    
    func testDisabledCachePolicy() async throws {
        let request = GetUsersNoCacheRequest()
        XCTAssertEqual(request.cachePolicy, .disabled)
        XCTAssertFalse(request.cachePolicy.isCachingEnabled)
    }
    
    func testURLCachePolicyIsCachingEnabled() async throws {
        let request = GetUsersRequest()
        XCTAssertTrue(request.cachePolicy.isCachingEnabled)
    }
    
    // MARK: - Cache Method Tests
    
    func testCacheMethodReturnsNilForURLCachePolicy() async throws {
        let request = GetUsersRequest()
        
        // cache() should return nil for URLCache policy
        let cached = await request.cache()
        XCTAssertNil(cached, "cache() should return nil for URLCache policy")
    }
    
    func testCacheMethodReturnsNilForDisabledPolicy() async throws {
        let request = GetUsersNoCacheRequest()
        
        let cached = await request.cache()
        XCTAssertNil(cached, "cache() should return nil for disabled policy")
    }
    
    func testCacheMethodWorksForCustomPolicy() async throws {
        // Given
        let mockResponse = TestUser(id: 1, name: "John", email: "john@example.com")
        let jsonData = try JSONEncoder().encode(mockResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = await HMock(request: GetUsersWithCustomCacheRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        // When
        let request = GetUsersWithCustomCacheRequest()
        let _ = await request.request()
        
        // Then - cache should be available via custom cache
        let cached = await request.cache()
        XCTAssertNotNil(cached, "cache() should return data for custom cache policy")
        XCTAssertEqual(cached?.id, 1)
    }
    
    // MARK: - Clear Cache Tests
    
    func testClearCacheWorksForURLCache() async throws {
        let request = GetUsersRequest()
        
        // Should not crash - now supports URLCache
        await request.clearCache()
    }
    
    func testClearCacheWorksForCustomPolicy() async throws {
        // Given - populate custom cache
        let mockResponse = TestUser(id: 1, name: "John", email: "john@example.com")
        let jsonData = try JSONEncoder().encode(mockResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = await HMock(request: GetUsersWithCustomCacheRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = GetUsersWithCustomCacheRequest()
        let _ = await request.request()
        
        // When - clear cache
        await request.clearCache()
        
        // Then - cache should be empty
        let cached = await request.cache()
        XCTAssertNil(cached, "Cache should be cleared")
    }
    
    // MARK: - Custom URLCache Tests
    
    func testCustomURLCachePolicy() async throws {
        let customCache = URLCache(
            memoryCapacity: 100 * 1024 * 1024,
            diskCapacity: 500 * 1024 * 1024
        )
        let request = GetUsersCustomURLCacheRequest(urlCache: customCache)
        
        guard case .urlCache(let cache) = request.cachePolicy else {
            XCTFail("Expected urlCache policy")
            return
        }
        XCTAssertEqual(cache.memoryCapacity, 100 * 1024 * 1024)
        XCTAssertEqual(cache.diskCapacity, 500 * 1024 * 1024)
    }
}

// MARK: - Test Requests

private struct GetUsersRequest: HGetRequestProtocol {
    typealias Model = TestUser
    let url = "https://api.example.com/users"
    // Uses default cachePolicy = .urlCache()
}

private struct GetUsersWithCustomCacheRequest: HGetRequestProtocol {
    typealias Model = TestUser
    let url = "https://api.example.com/users"
    let cachePolicy: HCache.Policy = .custom(HCache.Configuration(expirationTime: .oneHour))
}

private struct GetUsersNoCacheRequest: HGetRequestProtocol {
    typealias Model = TestUser
    let url = "https://api.example.com/users"
    let cachePolicy: HCache.Policy = .disabled
}

private struct GetUsersCustomURLCacheRequest: HGetRequestProtocol {
    typealias Model = TestUser
    let url = "https://api.example.com/users"
    let cachePolicy: HCache.Policy
    
    init(urlCache: URLCache) {
        self.cachePolicy = .urlCache(urlCache)
    }
}

// MARK: - Test Models

private struct TestUser: Codable, Sendable {
    let id: Int
    let name: String
    let email: String
}

