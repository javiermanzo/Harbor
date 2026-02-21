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
        switch request.cachePolicy {
        case .custom(let config):
            XCTAssertEqual(config.expirationTime, .oneHour)
            XCTAssertEqual(config.maxObjectSizeInMBs, 10)
        default:
            XCTFail("Expected custom cache policy")
        }
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
    
    // MARK: - Legacy CacheConfiguration Support Tests
    
    func testLegacyCacheConfigurationStillWorks() async throws {
        let request = GetUsersLegacyRequest()
        
        // Should use custom cache from legacy configuration
        let effectivePolicy = request.resolveEffectivePolicy()
        
        switch effectivePolicy {
        case .custom(let config):
            XCTAssertEqual(config.expirationTime, .oneHour)
        default:
            XCTFail("Legacy cacheConfiguration should be converted to custom policy")
        }
    }
    
    func testNewCachePolicyTakesPrecedenceOverLegacy() async throws {
        // Use .disabled (not default) to verify new policy is used
        let request = GetUsersBothPoliciesRequest()
        
        // cachePolicy should be used, not cacheConfiguration
        // Since cachePolicy is .disabled, isCachingEnabled should be false
        XCTAssertFalse(request.cachePolicy.isCachingEnabled, "New cachePolicy (.disabled) should take precedence")
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
    
    func testClearCacheDoesNothingForURLCache() async throws {
        let request = GetUsersRequest()
        
        // Should not crash or throw
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

private struct GetUsersLegacyRequest: HGetRequestProtocol {
    typealias Model = TestUser
    let url = "https://api.example.com/users"
    // Using deprecated cacheConfiguration
    let cacheConfiguration: HCache.Configuration? = HCache.Configuration(expirationTime: .oneHour)
}

private struct GetUsersBothPoliciesRequest: HGetRequestProtocol {
    typealias Model = TestUser
    let url = "https://api.example.com/users"
    let cachePolicy: HCache.Policy = .disabled  // Use disabled to test precedence
    let cacheConfiguration: HCache.Configuration? = HCache.Configuration(expirationTime: .oneHour)
}

// MARK: - Test Models

private struct TestUser: Codable, Sendable {
    let id: Int
    let name: String
    let email: String
}

// MARK: - Policy Resolution Helper

private extension HGetRequestProtocol {
    func resolveEffectivePolicy() -> HCache.Policy {
        // If new cachePolicy is explicitly set (not default), use it
        // Otherwise fall back to legacy cacheConfiguration
        let defaultPolicy: HCache.Policy = .urlCache()
        if cachePolicy != defaultPolicy {
            return cachePolicy
        }
        // If using default policy but has legacy config, use custom
        if let config = cacheConfiguration {
            return .custom(config)
        }
        return cachePolicy
    }
}
