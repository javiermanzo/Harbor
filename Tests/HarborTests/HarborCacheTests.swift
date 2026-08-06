//
//  HarborCacheTests.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import XCTest
@testable import Harbor

@HRequestManagerActor
final class HarborCacheTests: XCTestCase {

    override func setUp() async throws {
        // Clear all cache before each test
        await Harbor.clearAllCache()
        await Harbor.removeAllMocks()
        await Harbor.setMocksOnlyInDebug(false)
        // Set default cache to disabled (original behavior)
        await Harbor.setDefaultCacheType(.disabled)
    }

    override func tearDown() async throws {
        // Clear all cache after each test
        await Harbor.clearAllCache()
        await Harbor.removeAllMocks()
        await Harbor.setDefaultCacheType(.disabled)
    }
    
    // MARK: - Cache Configuration Tests
    
    func testCacheDefaultValue() async {
        let request = TestDefaultCacheableRequest()
        XCTAssertNil(request.cacheType, "Cache type should be nil by default (uses config default)")
    }
    
    func testCacheUsesDefaultFromConfig() async {
        // Requests with no explicit cache type use the global default
        await Harbor.setDefaultCacheType(.custom(HCache.Configuration(expirationTime: .oneHour)))

        let testData = TestCacheData(value: "default-config-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }

        let mock = HMock(request: TestDefaultCacheableRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)

        let request = TestDefaultCacheableRequest() // cacheType is nil
        let response = await request.request()
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "default-config-test")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }

        let cachedData = await request.cache()
        XCTAssertNotNil(cachedData, "Request without explicit cache type should be cached under the global default")

        await Harbor.removeAllMocks()
    }

    func testClearCacheRespectsDefaultCacheType() async {
        await Harbor.setDefaultCacheType(.custom(HCache.Configuration()))

        let testData = TestCacheData(value: "clear-default-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }

        let mock = HMock(request: TestDefaultCacheableRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)

        let request = TestDefaultCacheableRequest() // cacheType is nil, uses the global default
        _ = await request.request()

        let cachedData = await request.cache()
        XCTAssertNotNil(cachedData, "Data should be cached under the global default cache type")

        await request.clearCache()

        let cachedDataAfterClear = await request.cache()
        XCTAssertNil(cachedDataAfterClear, "clearCache should remove data cached under the global default cache type")

        await Harbor.removeAllMocks()
    }
    
    func testCacheConfigurationDefaults() async {
        let request = TestCacheableRequest()
        guard case .custom(let config) = request.cacheType else {
            XCTFail("Cache type should be custom for TestCacheableRequest")
            return
        }
        // TestCacheableRequest uses HCache.Configuration() with default values
        XCTAssertEqual(config.maxObjectSizeInMBs, 10)
        XCTAssertEqual(config.memoryCacheCapacityInMBs, 100)
    }
    
    func testExplicitlyDisabledCache() async {
        let testData = TestCacheData(value: "disabled-cache-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = HMock(request: TestExplicitlyDisabledRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestExplicitlyDisabledRequest()
        
        // Verify cache is explicitly disabled via type
        XCTAssertEqual(request.cacheType, .disabled, "Cache type should be disabled")

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
    
    func testCacheKeyGeneration() async throws {
        let request = TestCacheableRequest()
        let expectedKey = "https://cache.example.com/test"
        let actualKey = try HURLBuilder.compositeURL(url: request.url, pathParameters: request.pathParameters, queryParameters: request.queryParameters).absoluteString
        XCTAssertEqual(actualKey, expectedKey, "Cache key should match the URL")
    }
    
    func testCacheKeyWithQueryParameters() async throws {
        let request = TestCacheableGetRequest()
        let expectedKey = "https://cache.example.com/test?limit=10&page=1"
        let actualKey = try HURLBuilder.compositeURL(url: request.url, pathParameters: request.pathParameters, queryParameters: request.queryParameters).absoluteString
        XCTAssertEqual(actualKey, expectedKey, "Cache key should include sorted query parameters")
    }
    
    func testCacheKeyWithPathParameters() async throws {
        let request = TestCacheablePathRequest()
        let expectedKey = "https://cache.example.com/users/123"
        let actualKey = try HURLBuilder.compositeURL(url: request.url, pathParameters: request.pathParameters, queryParameters: request.queryParameters).absoluteString
        XCTAssertEqual(actualKey, expectedKey, "Cache key should substitute path parameters")
    }
    
    // MARK: - Cache Expiration Tests
    
    func testCustomCacheExpirationTime() async {
        let testData = TestCacheData(value: "custom-expiration-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = HMock(request: TestCustomExpirationRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestCustomExpirationRequest()
        guard case .custom(let config) = request.cacheType else {
            XCTFail("Cache type should be custom for TestCustomExpirationRequest")
            return
        }
        XCTAssertEqual(config.expirationTime, 60, "Custom expiration time should be 60 seconds")
        
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
        // A zero-second expiration makes the entry stale immediately
        let testData = TestCacheData(value: "expired-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }

        let mock = HMock(request: TestZeroExpirationRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)

        let request = TestZeroExpirationRequest()

        // First request stores in cache
        _ = await request.request()
        await HCache.Manager.shared.waitForPendingDiskOperations()

        // Should not retrieve the immediately expired data
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
        
        let mock = HMock(request: TestOneHourCacheRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestOneHourCacheRequest()
        guard case .custom(let config) = request.cacheType else {
            XCTFail("Cache type should be custom for TestOneHourCacheRequest")
            return
        }
        XCTAssertEqual(config.expirationTime, .oneHour, "Should use oneHour constant")
        XCTAssertEqual(config.expirationTime, 3600, "OneHour should equal 3600 seconds")
        
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
    
    func testTimeIntervalConstants() async {
        XCTAssertNil(TimeInterval.noExpiration, "TimeInterval.noExpiration should be nil")
        XCTAssertEqual(TimeInterval.oneHour, 3600, "OneHour should be 3600 seconds")
        XCTAssertEqual(TimeInterval.oneDay, 86400, "OneDay should be 86400 seconds")
        XCTAssertEqual(TimeInterval.oneWeek, 604800, "OneWeek should be 604800 seconds")
        XCTAssertEqual(TimeInterval.oneMonth, 2592000, "OneMonth should be 2592000 seconds")
        XCTAssertEqual(TimeInterval.oneYear, 31536000, "OneYear should be 31536000 seconds")
    }
    
    // MARK: - HTTP Header Priority Tests
    
    func testCacheControlMaxAgeOverridesConfig() async {
        // The response max-age takes precedence over the configured expiration:
        // the config allows 1 hour, but max-age=0 makes the entry stale immediately.
        let testData = TestCacheData(value: "cache-control-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }

        let mock = HMock(
            request: TestLongCacheRequest.self,
            statusCode: 200,
            jsonResponse: jsonString,
            headers: ["Cache-Control": "max-age=0"]
        )
        await Harbor.register(mock: mock)

        let request = TestLongCacheRequest() // This has 1 hour expiration in config

        let response = await request.request()

        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "cache-control-test")

            let cachedEntry = await request.cache()
            XCTAssertNil(cachedEntry, "max-age=0 should override the 1 hour config expiration")

        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }

        await Harbor.removeAllMocks()

        // The opposite direction also holds: an immediately expiring config is
        // overridden by a positive max-age from the response.
        let mock2 = HMock(
            request: TestZeroExpirationRequest.self,
            statusCode: 200,
            jsonResponse: jsonString,
            headers: ["Cache-Control": "max-age=3600"]
        )
        await Harbor.register(mock: mock2)

        let request2 = TestZeroExpirationRequest() // Config expires immediately
        let response2 = await request2.request()

        switch response2 {
        case .success:
            let cachedEntry2 = await request2.cache()
            XCTAssertNotNil(cachedEntry2, "max-age=3600 should override the 0 seconds config expiration")
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
        
        let mock = HMock(
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
        // no-cache stores the entry but never serves it without revalidation,
        // while keeping its validators available for conditional requests.
        let testData = TestCacheData(value: "no-cache-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }

        let mock = HMock(
            request: TestNoCacheRequest.self,
            statusCode: 200,
            jsonResponse: jsonString,
            headers: ["Cache-Control": "no-cache", "ETag": "\"no-cache-etag\""]
        )
        await Harbor.register(mock: mock)

        let request = TestNoCacheRequest()
        let response = await request.request()

        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "no-cache-test")

            await HCache.Manager.shared.waitForPendingDiskOperations()

            let cachedEntry = await request.cache()
            XCTAssertNil(cachedEntry, "no-cache entries must not be served without revalidation")

            let cachedETag = await request.cachedETag()
            XCTAssertEqual(cachedETag, "\"no-cache-etag\"", "no-cache entries keep their ETag for revalidation")

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
        
        // The no-cache directive does not alter the expiration time; entries are
        // marked always stale at store time instead, so the fallback applies here
        let response3 = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                      headerFields: ["Cache-Control": "no-cache"])
        let result3 = await HCache.Manager.shared.calculateEffectiveExpirationTime(fromResponse: response3, fallbackTime: 7200)
        XCTAssertEqual(result3, 7200, "Should use the fallback time for the no-cache directive")
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
        
        let mock = HMock(request: TestCacheableRequest.self, statusCode: 200, jsonResponse: jsonString)
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
        
        let mock = HMock(request: TestDefaultCacheableRequest.self, statusCode: 200, jsonResponse: jsonString)
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
        let mock = HMock(request: TestCacheableRequest.self, statusCode: 200, jsonResponse: jsonString)
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
        
        let mock = HMock(request: TestCacheableRequest.self, statusCode: 200, jsonResponse: jsonString)
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
        
        let mock = HMock(request: TestCacheableRequest.self, statusCode: 200, jsonResponse: jsonString)
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

    // MARK: - Shared URLCache Tests

    func testHarborClearAllCacheClearsSharedURLCache() async {
        let url = URL(string: "https://cache.example.com/shared-url-cache")!
        let urlRequest = URLRequest(url: url)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!

        URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: Data("shared".utf8)), for: urlRequest)
        XCTAssertNotNil(URLCache.shared.cachedResponse(for: urlRequest), "Entry should be stored in URLCache.shared")

        await Harbor.clearAllCache()

        XCTAssertNil(URLCache.shared.cachedResponse(for: urlRequest), "clearAllCache should clear URLCache.shared")
    }

    // MARK: - Capacity Configuration Tests

    func testMemoryCacheCapacityIsApplied() async {
        let config = HCache.Configuration(memoryCacheCapacityInMBs: 2)
        let data = Data("memory-capacity".utf8)

        await HCache.Manager.shared.storeData(data, forKey: "https://cache.example.com/memory-capacity", config: config, response: nil)

        XCTAssertEqual(HCache.Manager.shared.memoryCacheCostLimit, 2 * 1024 * 1024, "Memory cache cost limit should reflect the configuration")
    }

    func testConfigurationClampsCapacitiesToMinimum() async {
        let config = HCache.Configuration(maxObjectSizeInMBs: 0, memoryCacheCapacityInMBs: -5, diskCacheCapacityInMBs: 0)

        XCTAssertEqual(config.maxObjectSizeInMBs, 1, "maxObjectSizeInMBs below 1 should clamp to 1")
        XCTAssertEqual(config.memoryCacheCapacityInMBs, 1, "memoryCacheCapacityInMBs below 1 should clamp to 1")
        XCTAssertEqual(config.diskCacheCapacityInMBs, 1, "diskCacheCapacityInMBs below 1 should clamp to 1")
    }

    func testMaxObjectSizeIsInclusive() async {
        let config = HCache.Configuration(maxObjectSizeInMBs: 1)
        let data = Data(count: config.maxObjectSizeInBytes)
        let key = "https://cache.example.com/max-object-inclusive"

        await HCache.Manager.shared.storeData(data, forKey: key, config: config, response: nil)
        await HCache.Manager.shared.waitForPendingDiskOperations()

        let fileURL = HCache.Manager.shared.cacheDirectory
            .appendingPathComponent(key.sha256Hex)
            .appendingPathExtension("cache")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Data of exactly maxObjectSizeInBytes should be cached")
    }

    // MARK: - Cache-Control Directive Tests

    func testNoStoreDirectiveIsNotPersisted() async {
        let testData = TestCacheData(value: "no-store-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }

        let mock = HMock(
            request: TestNoStoreRequest.self,
            statusCode: 200,
            jsonResponse: jsonString,
            headers: ["Cache-Control": "no-store", "ETag": "\"no-store-etag\""]
        )
        await Harbor.register(mock: mock)

        let request = TestNoStoreRequest()
        let response = await request.request()
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "no-store-test")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }

        await HCache.Manager.shared.waitForPendingDiskOperations()

        let cachedData = await request.cache()
        XCTAssertNil(cachedData, "no-store responses must not be persisted")

        let cachedETag = await request.cachedETag()
        XCTAssertNil(cachedETag, "no-store responses must not keep validators")

        await Harbor.removeAllMocks()
    }

    func testLowercaseResponseHeadersAreHonored() async {
        let testData = TestCacheData(value: "lowercase-headers-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }

        let mock = HMock(
            request: TestLowercaseHeadersRequest.self,
            statusCode: 200,
            jsonResponse: jsonString,
            headers: ["cache-control": "max-age=3600", "etag": "\"lowercase-etag\""]
        )
        await Harbor.register(mock: mock)

        let request = TestLowercaseHeadersRequest()
        let response = await request.request()
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "lowercase-headers-test")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }

        let cachedData = await request.cache()
        XCTAssertNotNil(cachedData, "Directives from lowercase header names should be honored")

        let cachedETag = await request.cachedETag()
        XCTAssertEqual(cachedETag, "\"lowercase-etag\"", "ETag from a lowercase header name should be stored")

        await Harbor.removeAllMocks()
    }

    // MARK: - Vary Tests

    func testVaryHeaderIsEnforced() async {
        let testData = TestCacheData(value: "vary-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }

        let mock = HMock(
            request: TestVaryEnRequest.self,
            statusCode: 200,
            jsonResponse: jsonString,
            headers: ["Vary": "Accept-Language"]
        )
        await Harbor.register(mock: mock)

        let enRequest = TestVaryEnRequest()
        let response = await enRequest.request()
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "vary-test")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }

        let enCached = await enRequest.cache()
        XCTAssertNotNil(enCached, "The stored variant should be served for matching request headers")

        let esCached = await TestVaryEsRequest().cache()
        XCTAssertNil(esCached, "The stored variant must not be served for different Vary header values")

        let enCachedAgain = await enRequest.cache()
        XCTAssertNotNil(enCachedAgain, "A vary mismatch must be a miss, not an eviction of the stored variant")

        await Harbor.removeAllMocks()
    }

    // MARK: - Revalidation Tests

    func testNotModifiedRevalidationServesCachedBody() async throws {
        let testData = TestCacheData(value: "revalidation-body", timestamp: Date())
        let jsonData = try JSONEncoder().encode(testData)

        let request = TestRevalidationRequest()
        let key = try HURLBuilder.compositeURL(url: request.url, pathParameters: request.pathParameters, queryParameters: request.queryParameters).absoluteString

        // Pre-store an immediately expired entry that carries a validator
        let url = try XCTUnwrap(URL(string: request.url))
        let storeResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Cache-Control": "max-age=0", "ETag": "\"abc\""]
        )
        await HCache.Manager.shared.storeData(jsonData, forKey: key, config: HCache.Configuration(), response: storeResponse)
        await HCache.Manager.shared.waitForPendingDiskOperations()

        let cachedBefore = await request.cache()
        XCTAssertNil(cachedBefore, "Expired entries must not be served directly")

        // The outgoing request carries the stored validator as a conditional header
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "If-None-Match"), "\"abc\"")

        let mock = HMock(
            request: TestRevalidationRequest.self,
            statusCode: 304,
            headers: ["Cache-Control": "max-age=3600"]
        )
        await Harbor.register(mock: mock)

        let response = await request.request()
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "revalidation-body", "A 304 should be satisfied with the cached body")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }

        // The entry was refreshed with the new max-age and is servable again
        let cachedAfter = await request.cache()
        XCTAssertEqual(cachedAfter?.value, "revalidation-body", "The refreshed entry should be served from cache")

        await Harbor.removeAllMocks()
    }

    func testExpiredEntryWithoutValidatorsIsEvicted() async throws {
        let testData = TestCacheData(value: "expired-no-validator", timestamp: Date())
        let jsonData = try JSONEncoder().encode(testData)

        let key = "https://cache.example.com/expired-no-validator"
        let url = try XCTUnwrap(URL(string: key))
        let storeResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Cache-Control": "max-age=0"]
        )

        await HCache.Manager.shared.storeData(jsonData, forKey: key, config: HCache.Configuration(), response: storeResponse)
        await HCache.Manager.shared.waitForPendingDiskOperations()

        let fileURL = HCache.Manager.shared.cacheDirectory
            .appendingPathComponent(key.sha256Hex)
            .appendingPathExtension("cache")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Entry should be persisted on disk")

        // The first read drops the stale entry from memory; the next read reaches
        // the disk entry and evicts it because it carries no validators.
        let config = HCache.Configuration()
        let firstRead: TestCacheData? = await HCache.Manager.shared.getCachedData(forKey: key, type: TestCacheData.self, config: config)
        XCTAssertNil(firstRead, "Expired data must not be served")

        let secondRead: TestCacheData? = await HCache.Manager.shared.getCachedData(forKey: key, type: TestCacheData.self, config: config)
        XCTAssertNil(secondRead, "Expired data must not be served")

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "Expired entries without validators should be evicted from disk")
    }

    // MARK: - Stale-If-Error Tests

    func testStaleIfErrorServesExpiredEntryOnError() async {
        let testData = TestCacheData(value: "stale-body", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }

        let successMock = HMock(
            request: TestStaleOnErrorRequest.self,
            statusCode: 200,
            jsonResponse: jsonString,
            headers: ["Cache-Control": "max-age=0, stale-if-error=3600"]
        )
        await Harbor.register(mock: successMock)

        let request = TestStaleOnErrorRequest()
        _ = await request.request()

        await Harbor.removeAllMocks()

        let errorMock = HMock(request: TestStaleOnErrorRequest.self, statusCode: 500)
        await Harbor.register(mock: errorMock)

        let response = await request.request()
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "stale-body", "Errors should be served the stale body within the stale-if-error window")
        case .error(let error):
            XCTFail("Expected stale success but got error: \(error)")
        }

        await Harbor.removeAllMocks()
    }

    func testStaleIfErrorRespectsMustRevalidate() async {
        let testData = TestCacheData(value: "must-revalidate-body", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }

        let successMock = HMock(
            request: TestStaleOnErrorMustRevalidateRequest.self,
            statusCode: 200,
            jsonResponse: jsonString,
            headers: ["Cache-Control": "max-age=0, stale-if-error=3600, must-revalidate"]
        )
        await Harbor.register(mock: successMock)

        let request = TestStaleOnErrorMustRevalidateRequest()
        _ = await request.request()

        await Harbor.removeAllMocks()

        let errorMock = HMock(request: TestStaleOnErrorMustRevalidateRequest.self, statusCode: 500)
        await Harbor.register(mock: errorMock)

        let response = await request.request()
        switch response {
        case .success:
            XCTFail("must-revalidate entries must never be served stale")
        case .error(let error):
            guard case .api(let statusCode, _) = error else {
                XCTFail("Expected API error but got: \(error)")
                return
            }
            XCTAssertEqual(statusCode, 500)
        }

        await Harbor.removeAllMocks()
    }

    func testStaleIfErrorServesExpiredEntryWithoutConnection() async throws {
        let testData = TestCacheData(value: "offline-stale-body", timestamp: Date())
        let jsonData = try JSONEncoder().encode(testData)

        let request = TestStaleOfflineRequest()
        let key = try HURLBuilder.compositeURL(url: request.url, pathParameters: request.pathParameters, queryParameters: request.queryParameters).absoluteString

        let url = try XCTUnwrap(URL(string: request.url))
        let storeResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Cache-Control": "max-age=0, stale-if-error=3600"]
        )
        await HCache.Manager.shared.storeData(jsonData, forKey: key, config: HCache.Configuration(), response: storeResponse)
        await HCache.Manager.shared.waitForPendingDiskOperations()

        HRequestManager.connectivityMonitor = FakeConnectivityMonitor(connected: false)
        defer { HRequestManager.connectivityMonitor = HRequestManagerMonitor() }

        let response = await request.request()
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "offline-stale-body", "The connectivity pre-check should fall back to a servable stale entry")
        case .error(let error):
            XCTFail("Expected stale success but got error: \(error)")
        }
    }

    // MARK: - URLSession Isolation Tests

    func testGetURLSessionIsolation() async {
        let customSession = HRequestManager.getURLSession(for: TestCacheableRequest())
        XCTAssertEqual(customSession.configuration.urlCache?.memoryCapacity, 0, "Custom cache type should use an isolated zero-capacity URLCache")
        XCTAssertEqual(customSession.configuration.urlCache?.diskCapacity, 0, "Custom cache type should use an isolated zero-capacity URLCache")

        let disabledSession = HRequestManager.getURLSession(for: TestExplicitlyDisabledRequest())
        XCTAssertEqual(disabledSession.configuration.urlCache?.memoryCapacity, 0, "Disabled cache type should use an isolated zero-capacity URLCache")
        XCTAssertEqual(disabledSession.configuration.urlCache?.diskCapacity, 0, "Disabled cache type should use an isolated zero-capacity URLCache")

        let dedicatedCache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 2 * 1024 * 1024)
        let urlCacheSession = HRequestManager.getURLSession(for: TestDedicatedURLCacheRequest(urlCache: dedicatedCache))
        XCTAssertTrue(urlCacheSession.configuration.urlCache === dedicatedCache, "urlCache cache type should use the provided URLCache")
        XCTAssertEqual(urlCacheSession.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData, "urlCache cache type should use the provided cache policy")

        // A user-provided session is returned as-is
        let providedSession = URLSession(configuration: .default)
        await Harbor.setCustomURLSession(providedSession)
        let session = HRequestManager.getURLSession(for: TestCacheableRequest())
        XCTAssertTrue(session === providedSession, "A user-provided session should be returned as-is")
        HConfig.shared.customURLSession = nil
    }

    // MARK: - Cache-Control Parsing Unit Tests

    func testParseCacheControlDirectives() async {
        let noStore = HCache.Manager.parseCacheControlDirectives("no-store")
        XCTAssertTrue(noStore.noStore)
        XCTAssertFalse(noStore.noCache)
        XCTAssertNil(noStore.maxAge)

        let maxAgeNoStore = HCache.Manager.parseCacheControlDirectives("max-age=60, no-store")
        XCTAssertEqual(maxAgeNoStore.maxAge, 60)
        XCTAssertTrue(maxAgeNoStore.noStore)

        let malformedMaxAge = HCache.Manager.parseCacheControlDirectives("max-age=abc")
        XCTAssertNil(malformedMaxAge.maxAge, "Malformed directive values should be ignored")

        let uppercase = HCache.Manager.parseCacheControlDirectives("MAX-AGE=10")
        XCTAssertEqual(uppercase.maxAge, 10, "Directive parsing should be case-insensitive")

        let shared = HCache.Manager.parseCacheControlDirectives("s-maxage=120, max-age=60")
        XCTAssertEqual(shared.sMaxAge, 120)
        XCTAssertEqual(shared.maxAge, 60)

        let staleIfError = HCache.Manager.parseCacheControlDirectives("stale-if-error=30")
        XCTAssertEqual(staleIfError.staleIfError, 30)

        let mustRevalidate = HCache.Manager.parseCacheControlDirectives("must-revalidate")
        XCTAssertTrue(mustRevalidate.mustRevalidate)

        let isPublic = HCache.Manager.parseCacheControlDirectives("public")
        XCTAssertTrue(isPublic.isPublic)
        XCTAssertFalse(isPublic.isPrivate)

        let isPrivate = HCache.Manager.parseCacheControlDirectives("private")
        XCTAssertTrue(isPrivate.isPrivate)
        XCTAssertFalse(isPrivate.isPublic)

        let quotedMaxAge = HCache.Manager.parseCacheControlDirectives("max-age=\"3600\"")
        XCTAssertEqual(quotedMaxAge.maxAge, 3600, "Quoted directive values should be parsed")

        let quotedStaleIfError = HCache.Manager.parseCacheControlDirectives("stale-if-error=\"1800\"")
        XCTAssertEqual(quotedStaleIfError.staleIfError, 1800, "Quoted directive values should be parsed")
    }

    // MARK: - HTTP Date Parsing Unit Tests

    func testParseHTTPDate() async {
        let expectedTimestamp: TimeInterval = 784111777 // Sun, 06 Nov 1994 08:49:37 GMT

        let imfFixdate = HCache.Manager.parseHTTPDate("Sun, 06 Nov 1994 08:49:37 GMT")
        XCTAssertEqual(imfFixdate?.timeIntervalSince1970, expectedTimestamp, "Should parse IMF-fixdate")

        let rfc850 = HCache.Manager.parseHTTPDate("Sunday, 06-Nov-94 08:49:37 GMT")
        XCTAssertEqual(rfc850?.timeIntervalSince1970, expectedTimestamp, "Should parse RFC 850")

        let asctime = HCache.Manager.parseHTTPDate("Sun Nov  6 08:49:37 1994")
        XCTAssertEqual(asctime?.timeIntervalSince1970, expectedTimestamp, "Should parse asctime")

        XCTAssertNil(HCache.Manager.parseHTTPDate("not a date"), "Malformed strings should not parse")
        XCTAssertNil(HCache.Manager.parseHTTPDate(""), "Empty strings should not parse")
        XCTAssertNil(HCache.Manager.parseHTTPDate("1994-11-06T08:49:37Z"), "ISO 8601 is not an HTTP-date format")

        let pastDate = HCache.Manager.parseHTTPDate("Mon, 01 Jan 1990 00:00:00 GMT")
        XCTAssertNotNil(pastDate)
        XCTAssertTrue(pastDate! < Date(), "Past dates should parse to a date in the past")
    }

    // MARK: - Empty Response Tests

    func testEmptyResponseNotModifiedReturnsSuccess() async {
        let mock = HMock(request: TestEmptyResponseRequest.self, statusCode: 304)
        await Harbor.register(mock: mock)

        let response = await TestEmptyResponseRequest().request()
        switch response {
        case .success:
            break
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }

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
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration())
}

private struct TestDefaultCacheableRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    let url: String = "https://cache.example.com/non-cached" 
    // cache defaults to nil (uses HConfig default)
}

private struct TestCacheableGetRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    let url: String = "https://cache.example.com/test"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration())
    let queryParameters: [String: String]? = ["page": "1", "limit": "10"]
}

private struct TestCacheablePathRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    let url: String = "https://cache.example.com/users/{userId}"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration())
    let pathParameters: [String: String]? = ["userId": "123"]
}

private struct TestCustomExpirationRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    let url: String = "https://cache.example.com/custom-expiration"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: 60))
}

private struct TestOneHourCacheRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    let url: String = "https://cache.example.com/one-hour"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneHour))
}

private struct TestExplicitlyDisabledRequest: HGetRequestProtocol {
    typealias Model = TestCacheData

    let url: String = "https://cache.example.com/explicitly-disabled"
    let cacheType: HCache.CacheType? = .disabled
}

private struct TestLongCacheRequest: HGetRequestProtocol {
    typealias Model = TestCacheData
    
    var url: String = "https://cache.example.com/long-test"
    var cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneHour)) // 1 hour
}

private struct TestNoCacheRequest: HGetRequestProtocol {
    typealias Model = TestCacheData

    let url: String = "https://cache.example.com/no-cache-test"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration())
}

private struct TestZeroExpirationRequest: HGetRequestProtocol {
    typealias Model = TestCacheData

    let url: String = "https://cache.example.com/zero-expiration"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: 0))
}

private struct TestNoStoreRequest: HGetRequestProtocol {
    typealias Model = TestCacheData

    let url: String = "https://cache.example.com/no-store"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration())
}

private struct TestLowercaseHeadersRequest: HGetRequestProtocol {
    typealias Model = TestCacheData

    let url: String = "https://cache.example.com/lowercase-headers"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration())
}

private struct TestVaryEnRequest: HGetRequestProtocol {
    typealias Model = TestCacheData

    let url: String = "https://cache.example.com/vary"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration())
    var headerParameters: [String: String]? = ["Accept-Language": "en"]
}

private struct TestVaryEsRequest: HGetRequestProtocol {
    typealias Model = TestCacheData

    let url: String = "https://cache.example.com/vary"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration())
    var headerParameters: [String: String]? = ["Accept-Language": "es"]
}

private struct TestRevalidationRequest: HGetRequestProtocol {
    typealias Model = TestCacheData

    let url: String = "https://cache.example.com/revalidate"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration())
}

private struct TestStaleOnErrorRequest: HGetRequestProtocol {
    typealias Model = TestCacheData

    let url: String = "https://cache.example.com/stale-on-error"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration())
}

private struct TestStaleOnErrorMustRevalidateRequest: HGetRequestProtocol {
    typealias Model = TestCacheData

    let url: String = "https://cache.example.com/stale-on-error-must-revalidate"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration())
}

private struct TestStaleOfflineRequest: HGetRequestProtocol {
    typealias Model = TestCacheData

    let url: String = "https://cache.example.com/stale-offline"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration())
}

private struct TestDedicatedURLCacheRequest: HGetRequestProtocol {
    typealias Model = TestCacheData

    let url: String = "https://cache.example.com/dedicated-url-cache"
    let cacheType: HCache.CacheType?

    init(urlCache: URLCache) {
        self.cacheType = .urlCache(urlCache: urlCache, requestCachePolicy: .reloadIgnoringLocalCacheData)
    }
}

private struct TestEmptyResponseRequest: HRequestWithEmptyResponseProtocol {
    let url: String = "https://cache.example.com/empty-not-modified"
    var httpMethod: HHttpMethod { .get }
}
