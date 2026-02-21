//
//  HarborCacheTests.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import XCTest
@testable import Harbor

final class HarborCacheTests: XCTestCase {
    
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
    
    // MARK: - Cache Configuration Tests
    
    func testCacheDefaultValue() {
        let request = TestDefaultCacheableRequest()
        XCTAssertNil(request.cacheConfiguration, "Cache should be nil by default")
    }
    
    func testCacheUsesDefaultFromConfig() async {
        // Set default cache policy to custom with 1 hour expiration
        await Harbor.setDefaultCacheConfiguration(.custom(HCache.Configuration(expirationTime: .oneHour)))
        
        let request = TestCacheableRequest() // Uses explicit cache configuration
        let cachedData = await request.cache()
        
        // Since there's no cached data yet, should return nil
        XCTAssertNil(cachedData, "No cached data expected for new request")
        
        // Reset to disabled for other tests
        await Harbor.setDefaultCacheConfiguration(.disabled)
    }
    
    func testCacheConfigurationDefaults() {
        let request = TestCacheableRequest()
        guard let cache = request.cacheConfiguration else {
            XCTFail("Cache should not be nil for TestCacheableRequest")
            return
        }
        // TestCacheableRequest uses HCache.Configuration() with default values
        XCTAssertEqual(cache.maxObjectSizeInMBs, 10)
        XCTAssertEqual(cache.memoryCacheCapacityInMBs, 100)
    }
    
    func testExplicitlyDisabledCache() async {
        let testData = TestCacheData(value: "disabled-cache-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(request: TestExplicitlyDisabledRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestExplicitlyDisabledRequest()
        
        // Verify cache is explicitly disabled via policy
        XCTAssertEqual(request.cachePolicy, .disabled, "Cache policy should be disabled")
        
        // Make request
        let response = await request.request()
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "disabled-cache-test")
        case .error(_):
            XCTFail("Expected success but got error")
        }
        
        // Verify data is not cached
        let cachedData = await request.cache()
        XCTAssertNil(cachedData, "Explicitly disabled cache should not return cached data")
        
        await Harbor.removeAllMocks()
    }
    
    // MARK: - Cache Key Generation Tests
    
    func testCacheKeyGeneration() {
        let request = TestCacheableRequest()
        let expectedKey = "https://cache.example.com/test"
        XCTAssertEqual(request.cacheKey, expectedKey, "Cache key should match the URL")
    }
    
    func testCacheKeyWithQueryParameters() {
        let request = TestCacheableGetRequest()
        let expectedKey = "https://cache.example.com/test?limit=10&page=1"
        XCTAssertEqual(request.cacheKey, expectedKey, "Cache key should include sorted query parameters")
    }
    
    func testCacheKeyWithPathParameters() {
        let request = TestCacheablePathRequest()
        let expectedKey = "https://cache.example.com/users/123"
        XCTAssertEqual(request.cacheKey, expectedKey, "Cache key should substitute path parameters")
    }
    
    // MARK: - Cache Expiration Tests
    
    func testCustomCacheExpirationTime() async {
        let testData = TestCacheData(value: "custom-expiration-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(request: TestCustomExpirationRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestCustomExpirationRequest()
        guard let cache = request.cacheConfiguration else {
            XCTFail("Cache should not be nil for TestCustomExpirationRequest")
            return
        }
        XCTAssertEqual(cache.expirationTime, 60, "Custom expiration time should be 60 seconds")
        
        // Make request to cache data
        let response = await request.request()
        switch response {
        case .success:
            break
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
        
        // Check that data is cached with custom expiration
        let cachedData = await request.cache()
        XCTAssertNotNil(cachedData, "Request should have cached data")
    }
    
    func testCacheExpiration() async {
        // Test with custom short expiration request
        let testData = TestCacheData(value: "expired-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(request: TestVeryShortExpirationRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestVeryShortExpirationRequest()
        
        // First request stores in cache
        _ = await request.request()
        
        // Wait for expiration
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Should not retrieve expired data
        let cachedData = await request.cache()
        XCTAssertNil(cachedData, "Should not retrieve expired data")
        
        await Harbor.removeAllMocks()
    }
    
    func testCacheWithTimeIntervalConstants() async {
        let testData = TestCacheData(value: "time-interval-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(request: TestOneHourCacheRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestOneHourCacheRequest()
        guard let cache = request.cacheConfiguration else {
            XCTFail("Cache should not be nil for TestOneHourCacheRequest")
            return
        }
        XCTAssertEqual(cache.expirationTime, .oneHour, "Should use oneHour constant")
        XCTAssertEqual(cache.expirationTime, 3600, "OneHour should equal 3600 seconds")
        
        // Make request to cache data
        let response = await request.request()
        switch response {
        case .success:
            break
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
        
        // Check that data is cached
        let cachedData = await request.cache()
        XCTAssertNotNil(cachedData, "Request should have cached data")
    }
    
    func testTimeIntervalConstants() {
        XCTAssertNil(TimeInterval.none, "TimeInterval.none should be nil")
        XCTAssertEqual(TimeInterval.oneHour, 3600, "OneHour should be 3600 seconds")
        XCTAssertEqual(TimeInterval.oneDay, 86400, "OneDay should be 86400 seconds")
        XCTAssertEqual(TimeInterval.oneWeek, 604800, "OneWeek should be 604800 seconds")
        XCTAssertEqual(TimeInterval.oneMonth, 2592000, "OneMonth should be 2592000 seconds")
        XCTAssertEqual(TimeInterval.oneYear, 31536000, "OneYear should be 31536000 seconds")
    }
    
    // MARK: - HTTP Header Priority Tests
    
    func testCacheControlMaxAgeOverridesConfig() async {
        // Test Cache-Control max-age priority over config
        let testData = TestCacheData(value: "cache-control-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        // Create mock response
        let mock = await HMock(
            request: TestLongCacheRequest.self,
            statusCode: 200,
            jsonResponse: jsonString
        )
        await Harbor.register(mock: mock)
        
        // Configure request with longer expiration (1 hour)
        let request = TestLongCacheRequest() // This has 1 hour expiration in config
        
        // Make request
        let response = await request.request()
        
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "cache-control-test")
            
            // Verify that the cache entry uses the expected expiration
            let cachedEntry = await request.cache()
            XCTAssertNotNil(cachedEntry, "Data should be cached")
            
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
        
        await Harbor.removeAllMocks()
    }
    
    func testConfigFallbackWhenNoHeaders() async {
        // Mock without cache headers
        let testData = TestCacheData(value: "config-fallback-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(
            request: TestCacheableRequest.self,
            statusCode: 200,
            jsonResponse: jsonString
            // No cache headers
        )
        await Harbor.register(mock: mock)
        
        let request = TestCacheableRequest() // Uses config expiration
        let response = await request.request()
        
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "config-fallback-test")
            
            // Verify data is cached using config expiration
            let cachedEntry = await request.cache()
            XCTAssertNotNil(cachedEntry, "Data should be cached using config expiration")
            
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
        
        await Harbor.removeAllMocks()
    }
    
    func testNoCacheDirectivePreventsCaching() async {
        // Test with disabled cache configuration
        let testData = TestCacheData(value: "no-cache-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        // Create mock response
        let mock = await HMock(
            request: TestNoCacheRequest.self,
            statusCode: 200,
            jsonResponse: jsonString
        )
        await Harbor.register(mock: mock)
        
        let request = TestNoCacheRequest()
        let response = await request.request()
        
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "no-cache-test")
            
            // Wait a moment for cache operations to complete
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Verify data is NOT cached due to disabled cache configuration
            let cachedEntry = await request.cache()
            XCTAssertNil(cachedEntry, "Data should NOT be cached with disabled configuration")
            
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
        
        await Harbor.removeAllMocks()
    }
    
    // MARK: - Cache-Control Parsing Tests
    
    func testParseCacheControlMaxAge() async {
        // Test Cache-Control header parsing by using calculateEffectiveExpirationTime
        // which internally uses parseCacheControlMaxAge
        
        // Test max-age=3600
        let url = URL(string: "https://test.com")!
        let response1 = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", 
                                      headerFields: ["Cache-Control": "max-age=3600"])
        let result1 = await HCache.Manager.shared.calculateEffectiveExpirationTime(fromResponse: response1, fallbackTime: nil)
        XCTAssertEqual(result1, 3600, "Should parse max-age=3600 correctly")
        
        // Test max-age=1800 with other directives
        let response2 = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", 
                                      headerFields: ["Cache-Control": "public, max-age=1800"])
        let result2 = await HCache.Manager.shared.calculateEffectiveExpirationTime(fromResponse: response2, fallbackTime: nil)
        XCTAssertEqual(result2, 1800, "Should parse max-age=1800 correctly")
        
        // Test no-cache directive
        let response3 = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", 
                                      headerFields: ["Cache-Control": "no-cache"])
        let result3 = await HCache.Manager.shared.calculateEffectiveExpirationTime(fromResponse: response3, fallbackTime: 7200)
        XCTAssertEqual(result3, 0, "Should return 0 for no-cache directive")
    }
    
    func testParseExpiresHeader() async {
        // Test Expires header parsing by using calculateEffectiveExpirationTime
        
        // Create a future date for testing
        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        
        let validExpiresString = formatter.string(from: futureDate)
        let url = URL(string: "https://test.com")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", 
                                     headerFields: ["Expires": validExpiresString])
        
        let result = await HCache.Manager.shared.calculateEffectiveExpirationTime(fromResponse: response, fallbackTime: nil)
        
        XCTAssertNotNil(result)
        XCTAssertTrue(result! > 3500 && result! < 3700, "Should parse valid Expires header correctly")
        
        // Test invalid format
        let invalidResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", 
                                            headerFields: ["Expires": "invalid-date"])
        let invalidResult = await HCache.Manager.shared.calculateEffectiveExpirationTime(fromResponse: invalidResponse, fallbackTime: 1800)
        XCTAssertEqual(invalidResult, 1800, "Should fallback to provided time for invalid Expires header")
    }
    
    // MARK: - Cache Integration Tests
    
    func testCacheableRequestWithMock() async {
        let testData = TestCacheData(value: "integration-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(request: TestCacheableRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestCacheableRequest()
        
        // First request should hit mock and cache the result
        let firstResponse = await request.request()
        switch firstResponse {
        case .success(let data):
            XCTAssertEqual(data.value, "integration-test")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
        
        // Check if data is cached
        let cachedData = await request.cache()
        XCTAssertNotNil(cachedData, "Request should have cached data after first call")
        
        // Remove mock to ensure second request uses cache
        await Harbor.removeAllMocks()
        
        // Second request should use cache
        let cachedDataFromCache = await request.cache()
        XCTAssertNotNil(cachedDataFromCache, "Should retrieve data from cache")
        XCTAssertEqual(cachedDataFromCache?.value, "integration-test")
    }
    
    func testNonCacheableRequestDoesNotCache() async {
        // TestDefaultCacheableRequest uses default config which is disabled in setUp
        let testData = TestCacheData(value: "non-cached-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(request: TestDefaultCacheableRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestDefaultCacheableRequest()
        
        // Make request
        let response = await request.request()
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "non-cached-test")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
        
        // Check that data is not cached
        let cachedData = await request.cache()
        XCTAssertNil(cachedData, "Non-cacheable request should not cache data")
    }
    
    // MARK: - Harbor API Tests
    
    func testHarborClearCacheAPI() async {
        let testData = TestCacheData(value: "api-test", timestamp: Date())
        
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        // Test using request integration
        let mock = await HMock(request: TestCacheableRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestCacheableRequest()
        _ = await request.request() // Store in cache
        
        // Verify data exists
        let cachedDataBeforeClear = await request.cache()
        XCTAssertNotNil(cachedDataBeforeClear)
        
        // Clear cache via Harbor API
        await Harbor.clearAllCache()
        
        // Verify data is cleared
        let cachedDataAfterClear = await request.cache()
        XCTAssertNil(cachedDataAfterClear)
        
        await Harbor.removeAllMocks()
    }
    
    func testRequestCacheAPI() async {
        let testData = TestCacheData(value: "harbor-api-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(request: TestCacheableRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestCacheableRequest()
        
        // First request should hit mock and cache the result
        let firstResponse = await request.request()
        switch firstResponse {
        case .success(let data):
            XCTAssertEqual(data.value, "harbor-api-test")
        case .error(_):
            XCTFail("Expected success but got error")
        }
        
        // Test request.cache() API
        let cachedData = await request.cache()
        XCTAssertNotNil(cachedData, "request.cache() should return cached data")
        XCTAssertEqual(cachedData?.value, "harbor-api-test")
        
        await Harbor.removeAllMocks()
    }
    
    func testRequestClearCacheAPI() async {
        let testData = TestCacheData(value: "clear-cache-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(request: TestCacheableRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestCacheableRequest()
        
        // First request should hit mock and cache the result
        let firstResponse = await request.request()
        switch firstResponse {
        case .success(let data):
            XCTAssertEqual(data.value, "clear-cache-test")
        case .error(_):
            XCTFail("Expected success but got error")
        }
        
        // Verify data is cached
        let cachedData = await request.cache()
        XCTAssertNotNil(cachedData, "request.cache() should return cached data")
        
        // Clear cache for this specific request
        await request.clearCache()
        
        // Verify cache is cleared
        let cachedDataAfterClear = await request.cache()
        XCTAssertNil(cachedDataAfterClear, "request.cache() should return nil after clearCache()")
        
        await Harbor.removeAllMocks()
    }
}

// MARK: - Test Models and Requests

private struct TestCacheData: HModel {
    let value: String
    let timestamp: Date
}

private struct TestCacheableRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    let url: String = "https://cache.example.com/test"
    let cacheConfiguration: HCache.Configuration? = HCache.Configuration()
}

private struct TestDefaultCacheableRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    let url: String = "https://cache.example.com/non-cached" 
    // cache defaults to nil (uses HConfig default)
}

private struct TestCacheableGetRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    let url: String = "https://cache.example.com/test"
    let cacheConfiguration: HCache.Configuration? = HCache.Configuration()
    let queryParameters: [String: String]? = ["page": "1", "limit": "10"]
}

private struct TestCacheablePathRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    let url: String = "https://cache.example.com/users/{userId}"
    let cacheConfiguration: HCache.Configuration? = HCache.Configuration()
    let pathParameters: [String: String]? = ["userId": "123"]
}

private struct TestCustomExpirationRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    let url: String = "https://cache.example.com/custom-expiration"
    let cacheConfiguration: HCache.Configuration? = HCache.Configuration(expirationTime: 60)
}

private struct TestOneHourCacheRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    let url: String = "https://cache.example.com/one-hour"
    let cacheConfiguration: HCache.Configuration? = HCache.Configuration(expirationTime: .oneHour)
}

private struct TestExplicitlyDisabledRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    let url: String = "https://cache.example.com/explicitly-disabled"
    let cachePolicy: HCache.Policy = .disabled
}

private struct TestVeryShortExpirationRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    let url: String = "https://cache.example.com/very-short-expiration"
    let cachePolicy: HCache.Policy = .custom(HCache.Configuration(expirationTime: 0.01)) // 0.01 seconds
}

private struct TestLongCacheRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    var url: String = "https://cache.example.com/long-test"
    var cachePolicy: HCache.Policy = .custom(HCache.Configuration(expirationTime: .oneHour)) // 1 hour
}

private struct TestNoCacheRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    let url: String = "https://cache.example.com/no-cache-test"
    let cachePolicy: HCache.Policy = .disabled
}