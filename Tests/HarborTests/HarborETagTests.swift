//
//  HarborETagTests.swift
//  Harbor
//
//  Tests for ETag and cache type functionality
//

import XCTest
@testable import Harbor

@HRequestManagerActor
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
        XCTAssertNil(request.cacheType, "Default cache type should be nil (uses config default)")
    }
    
    func testCustomCachePolicy() async throws {
        let request = GetUsersWithCustomCacheRequest()
        guard case .custom(let config) = request.cacheType else {
            XCTFail("Expected custom cache type")
            return
        }
        XCTAssertEqual(config.expirationTime, .oneHour)
        XCTAssertEqual(config.maxObjectSizeInMBs, 10)
    }
    
    func testDisabledCachePolicy() async throws {
        let request = GetUsersNoCacheRequest()
        XCTAssertEqual(request.cacheType, .disabled)
        XCTAssertFalse(request.cacheType?.isCachingEnabled ?? false)
    }
    
    func testURLCachePolicyIsCachingEnabled() async throws {
        let request = GetUsersRequest()
        // Default cacheType is nil, but effective type .urlCache() has caching enabled
        let effectivePolicy = request.cacheType ?? .urlCache()
        XCTAssertTrue(effectivePolicy.isCachingEnabled)
    }
    
    // MARK: - Cache Method Tests
    
    func testCacheMethodReturnsNilForURLCachePolicy() async throws {
        let request = GetUsersRequest()
        
        // cache() should return nil for URLCache type
        let cached = await request.cache()
        XCTAssertNil(cached, "cache() should return nil for URLCache type")
    }
    
    func testCacheMethodReturnsNilForDisabledPolicy() async throws {
        let request = GetUsersNoCacheRequest()
        
        let cached = await request.cache()
        XCTAssertNil(cached, "cache() should return nil for disabled type")
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
        XCTAssertNotNil(cached, "cache() should return data for custom cache type")
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

        guard case .urlCache(let cache, _) = request.cacheType else {
            XCTFail("Expected urlCache type")
            return
        }
        XCTAssertEqual(cache.memoryCapacity, 100 * 1024 * 1024)
        XCTAssertEqual(cache.diskCapacity, 500 * 1024 * 1024)
    }

    // MARK: - ETag Tests

    func testCachedETagFromURLCache() async throws {
        let dedicatedCache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0)
        let request = GetUsersCustomURLCacheRequest(urlCache: dedicatedCache)

        let builtRequest = await HURLBuilder.buildUrlRequest(request: request)
        let urlRequest = try XCTUnwrap(builtRequest)
        let url = try XCTUnwrap(urlRequest.url)

        let user = TestUser(id: 1, name: "John", email: "john@example.com")
        let data = try JSONEncoder().encode(user)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["ETag": "\"url-cache-etag\""]
        ))
        dedicatedCache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: urlRequest)

        let cachedETag = await request.cachedETag()
        XCTAssertEqual(cachedETag, "\"url-cache-etag\"", "cachedETag should read the ETag from the URLCache entry")

        dedicatedCache.removeAllCachedResponses()
    }

    // MARK: - Cache Type Equality Tests

    func testCacheTypeURLCacheEquality() async throws {
        let cache1 = URLCache(memoryCapacity: 1024, diskCapacity: 1024)
        let cache2 = URLCache(memoryCapacity: 1024, diskCapacity: 1024)

        XCTAssertEqual(HCache.CacheType.urlCache(urlCache: cache1), .urlCache(urlCache: cache1), "Same cache instance should be equal")
        XCTAssertNotEqual(HCache.CacheType.urlCache(urlCache: cache1), .urlCache(urlCache: cache2), "Distinct cache instances should not be equal")
        XCTAssertNotEqual(
            HCache.CacheType.urlCache(urlCache: cache1, requestCachePolicy: .useProtocolCachePolicy),
            .urlCache(urlCache: cache1, requestCachePolicy: .reloadIgnoringLocalCacheData),
            "Different cache policies should not be equal"
        )
    }
}

// MARK: - Test Requests

private struct GetUsersRequest: HGetRequestProtocol {
    typealias Model = TestUser
    let url = "https://api.example.com/users"
    // Uses default cacheType = .urlCache()
}

private struct GetUsersWithCustomCacheRequest: HGetRequestProtocol {
    typealias Model = TestUser
    let url = "https://api.example.com/users"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneHour))
}

private struct GetUsersNoCacheRequest: HGetRequestProtocol {
    typealias Model = TestUser
    let url = "https://api.example.com/users"
    let cacheType: HCache.CacheType? = .disabled
}

private struct GetUsersCustomURLCacheRequest: HGetRequestProtocol {
    typealias Model = TestUser
    let url = "https://api.example.com/users"
    let cacheType: HCache.CacheType?
    
    init(urlCache: URLCache) {
        self.cacheType = .urlCache(urlCache: urlCache)
    }
}

// MARK: - Test Models

private struct TestUser: Codable, Sendable {
    let id: Int
    let name: String
    let email: String
}

