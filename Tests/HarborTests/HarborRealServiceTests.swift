//
//  HarborRealServiceTests.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import XCTest
@testable import Harbor

final class HarborRealServiceTests: XCTestCase {

    struct TestResource: HModel {
        let name: String
        let id: Int
    }

    struct GetTestResourceCustomCache: HGetRequestProtocol {
        typealias Model = TestResource
        let url = "https://pokeapi.co/api/v2/pokemon/ditto"
        let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: 60))
    }

    struct GetTestResourceURLCache: HGetRequestProtocol {
        typealias Model = TestResource
        let url = "https://pokeapi.co/api/v2/pokemon/mew"
        let queryParameters: [String: String]? = nil
        let cacheType: HCache.CacheType? = .urlCache()
    }

    struct GetTestResourceETag: HGetRequestProtocol {
        typealias Model = TestResource
        let url = "https://pokeapi.co/api/v2/pokemon/ditto"
        let cacheType: HCache.CacheType?

        init(urlCache: URLCache) {
            self.cacheType = .urlCache(urlCache: urlCache, requestCachePolicy: .useProtocolCachePolicy)
        }
    }

    /// Request with a long-lived custom cache for ETag tests.
    struct GetTestResourceCustomCacheETag: HGetRequestProtocol {
        typealias Model = TestResource
        let url = "https://pokeapi.co/api/v2/pokemon/ditto"
        // Long expiration so the entry does not expire during the test
        let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: 3600))
    }

    override func setUp() async throws {
        URLCache.shared.removeAllCachedResponses()
        LocalStubURLProtocol.clearStubs()

        let url = URL(string: "https://pokeapi.co/api/v2/pokemon/ditto")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "\"mocked-etag\""])!
        let data = "{\"name\": \"ditto\", \"id\": 132}".data(using: .utf8)!
        LocalStubURLProtocol.registerStub(for: url, data: data, response: response)

        let url2 = URL(string: "https://pokeapi.co/api/v2/pokemon/mew")!
        // URLCache entries are only served by cache() while fresh, so this stub carries
        // explicit freshness information.
        let response2 = HTTPURLResponse(url: url2, statusCode: 200, httpVersion: nil, headerFields: [
            "ETag": "\"mocked-etag-mew\"",
            "Cache-Control": "max-age=3600",
            "Date": Self.httpDate(Date())
        ])!
        LocalStubURLProtocol.registerStub(for: url2, data: data, response: response2)

        await Harbor.setProtocolClasses([LocalStubURLProtocol.self])
        await Harbor.removeAllMocks()
        await Harbor.clearAllCache()
        await Harbor.setMocksOnlyInDebug(false)
        await Harbor.setDefaultCacheType(.disabled)
    }

    /// Formats a date as an IMF-fixdate HTTP header value.
    private static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    override func tearDown() async throws {
        URLCache.shared.removeAllCachedResponses()
        await Harbor.setProtocolClasses(nil)
        await Harbor.removeAllMocks()
        await Harbor.clearAllCache()
    }

    func testRealNetworkConnection() async throws {
        try NetworkTestFlag.skipUnlessEnabled()
        await Harbor.setProtocolClasses(nil)
        let request = GetTestResourceCustomCache()
        let response = await request.request()
        switch response {
        case .success(let user):
            if user.name == "ditto" || user.name == "mew" {} else { XCTFail("Unexpected user name") }; XCTAssertTrue(user.name == "ditto" || user.name == "mew")
        case .error(let err):
            XCTFail("Request failed: \(err)")
        }
    }

    func testCustomCacheWithRealService() async throws {
        let request = GetTestResourceCustomCache()

        let initialCache = await request.cache()
        XCTAssertNil(initialCache)

        let response = await request.request()
        switch response {
        case .success(let user):
            if user.name == "ditto" || user.name == "mew" {} else { XCTFail("Unexpected user name") }; XCTAssertTrue(user.name == "ditto" || user.name == "mew")
        case .error(let err):
            XCTFail("Request failed: \(err)")
        }

        // Fetch from cache
        let cachedUser = await request.cache()
        XCTAssertNotNil(cachedUser)
        if cachedUser?.name == "ditto" || cachedUser?.name == "mew" {} else { XCTFail("Unexpected cached user name") }; XCTAssertTrue(cachedUser?.name == "ditto" || cachedUser?.name == "mew")
    }

    func testURLCacheWithRealService() async throws {
        let request = GetTestResourceURLCache()

        let initialCache = await request.cache()
        XCTAssertNil(initialCache)

        let response = await request.request()
        switch response {
        case .success(let user):
            if user.name == "ditto" || user.name == "mew" {} else { XCTFail("Unexpected user name") }; XCTAssertTrue(user.name == "ditto" || user.name == "mew")
        case .error(let err):
            XCTFail("Request failed: \(err)")
        }

        await waitForCachedResponse(of: request, in: .shared)

        let cachedUser = await request.cache()
        XCTAssertNotNil(cachedUser)
        if cachedUser?.name == "ditto" || cachedUser?.name == "mew" {} else { XCTFail("Unexpected cached user name") }; XCTAssertTrue(cachedUser?.name == "ditto" || cachedUser?.name == "mew")
    }

    func testCustomCacheRequestStream() async throws {
        let request = GetTestResourceCustomCache()

        // Populate cache
        let _ = await request.request()

        var resultsCount = 0
        do {
            for try await (response, _) in request.requestStream(source: .cacheAndRemote) {
                if response.name == "ditto" || response.name == "mew" {} else { XCTFail("Unexpected name") }; XCTAssertTrue(response.name == "ditto" || response.name == "mew")
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }

        XCTAssertEqual(resultsCount, 2, "Stream should return twice (once from cache, once from remote)")
    }

    func testURLCacheRequestStream() async throws {
        let request = GetTestResourceURLCache()

        // Populate cache
        let _ = await request.request()

        await waitForCachedResponse(of: request, in: .shared)

        var resultsCount = 0
        do {
            for try await (response, _) in request.requestStream(source: .cacheAndRemote) {
                if response.name == "ditto" || response.name == "mew" {} else { XCTFail("Unexpected name") }; XCTAssertTrue(response.name == "ditto" || response.name == "mew")
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }

        XCTAssertEqual(resultsCount, 2, "Stream should return twice (once from cache, once from remote)")
    }

    func testCustomCacheRequestStreamCacheOnly() async throws {
        let request = GetTestResourceCustomCache()

        let _ = await request.request()

        var resultsCount = 0
        do {
            for try await (response, origin) in request.requestStream(source: .cacheOnly) {
                if response.name == "ditto" || response.name == "mew" {} else { XCTFail("Unexpected name") }; XCTAssertTrue(response.name == "ditto" || response.name == "mew")
                XCTAssertEqual(origin, .cache)
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }
        XCTAssertEqual(resultsCount, 1, "Stream should return once from cache")
    }

    func testCustomCacheRequestStreamRemoteOnly() async throws {
        let request = GetTestResourceCustomCache()

        var resultsCount = 0
        do {
            for try await (response, origin) in request.requestStream(source: .remoteOnly) {
                if response.name == "ditto" || response.name == "mew" {} else { XCTFail("Unexpected name") }; XCTAssertTrue(response.name == "ditto" || response.name == "mew")
                XCTAssertEqual(origin, .remote)
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }
        XCTAssertEqual(resultsCount, 1, "Stream should return once from remote")
    }

    func testURLCacheRequestStreamCacheOnly() async throws {
        let request = GetTestResourceURLCache()

        // Populate cache
        let _ = await request.request()

        await waitForCachedResponse(of: request, in: .shared)

        var resultsCount = 0
        do {
            for try await (response, origin) in request.requestStream(source: .cacheOnly) {
                if response.name == "ditto" || response.name == "mew" {} else { XCTFail("Unexpected name") }; XCTAssertTrue(response.name == "ditto" || response.name == "mew")
                XCTAssertEqual(origin, .cache)
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }
        XCTAssertEqual(resultsCount, 1, "Stream should return once from cache")
    }

    func testURLCacheRequestStreamRemoteOnly() async throws {
        let request = GetTestResourceURLCache()

        var resultsCount = 0
        do {
            for try await (response, origin) in request.requestStream(source: .remoteOnly) {
                if response.name == "ditto" || response.name == "mew" {} else { XCTFail("Unexpected name") }; XCTAssertTrue(response.name == "ditto" || response.name == "mew")
                XCTAssertEqual(origin, .remote)
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }
        XCTAssertEqual(resultsCount, 1, "Stream should return once from remote")
    }

    // MARK: - ETag / 304 Not Modified Tests

    /// 1. Verifies that the real service returns an ETag header in the first response.
    func testETagHeaderIsReceivedFromRealService() async throws {
        let url = URL(string: "https://pokeapi.co/api/v2/pokemon/ditto")!
        var urlRequest = URLRequest(url: url)
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData

        let (_, response) = try await URLSession.shared.data(for: urlRequest)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)

        XCTAssertEqual(httpResponse.statusCode, 200)

        let etag = httpResponse.value(forHTTPHeaderField: "ETag")
            ?? httpResponse.value(forHTTPHeaderField: "Etag")
            ?? httpResponse.value(forHTTPHeaderField: "etag")
        XCTAssertNotNil(etag, "The service must return an ETag header")
        XCTAssertFalse(etag?.isEmpty ?? true, "The ETag must not be empty")
    }

    /// 2. Verifies that the server answers 304 Not Modified when the received ETag
    ///    is sent back through the If-None-Match header.
    func testETag304NotModifiedWithRealService() async throws {
        let url = URL(string: "https://pokeapi.co/api/v2/pokemon/ditto")!

        // First request: obtain the ETag
        var firstRequest = URLRequest(url: url)
        firstRequest.cachePolicy = .reloadIgnoringLocalCacheData

        let (_, firstResponse) = try await URLSession.shared.data(for: firstRequest)
        let firstHTTP = try XCTUnwrap(firstResponse as? HTTPURLResponse)
        XCTAssertEqual(firstHTTP.statusCode, 200)

        let etag = firstHTTP.value(forHTTPHeaderField: "ETag")
            ?? firstHTTP.value(forHTTPHeaderField: "Etag")
            ?? firstHTTP.value(forHTTPHeaderField: "etag")
        let unwrappedETag = try XCTUnwrap(etag, "The first response must contain an ETag")

        // Second request: send If-None-Match with the ETag we received
        var secondRequest = URLRequest(url: url)
        secondRequest.cachePolicy = .reloadIgnoringLocalCacheData
        secondRequest.setValue(unwrappedETag, forHTTPHeaderField: "If-None-Match")

        let (secondData, secondResponse) = try await URLSession.shared.data(for: secondRequest)
        let secondHTTP = try XCTUnwrap(secondResponse as? HTTPURLResponse)

        // The server must answer 304 Not Modified
        XCTAssertEqual(secondHTTP.statusCode, 304, "The server must answer 304 when the ETag has not changed")
        XCTAssertTrue(secondData.isEmpty, "A 304 must not carry a body")
    }

    /// 3. Verifies that Harbor, using URLCache with .useProtocolCachePolicy, handles the 304
    ///    transparently: the second request must still return data.
    func testETagCacheHitWithRealService() async throws {
        let urlCache = URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024)
        let request = GetTestResourceETag(urlCache: urlCache)

        // First request: fills the cache with the response and its ETag
        let firstResponse = await request.request()
        switch firstResponse {
        case .success(let user):
            if user.name == "ditto" || user.name == "mew" {} else { XCTFail("Unexpected user name") }; XCTAssertTrue(user.name == "ditto" || user.name == "mew")
        case .error(let err):
            XCTFail("First request failed: \(err)")
        }

        await waitForCachedResponse(of: request, in: urlCache)

        // Second request: URLSession sends If-None-Match automatically.
        // The server answers 304 and URLCache returns the cached body transparently.
        let secondResponse = await request.request()
        switch secondResponse {
        case .success(let user):
            XCTAssertEqual(user.name, "ditto", "The second request (304 handled by URLCache) must return the same data")
        case .error(let err):
            XCTFail("Second request (expected transparent 304 cache hit) failed: \(err)")
        }
    }

    /// 4. Verifies that requestStream works with URLCache and ETag.
    func testETagURLCacheRequestStream() async throws {
        let urlCache = URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024)
        let request = GetTestResourceETag(urlCache: urlCache)

        // First request: fills the cache
        let _ = await request.request()
        await waitForCachedResponse(of: request, in: urlCache)

        var resultsCount = 0
        do {
            for try await (response, _) in request.requestStream(source: .remoteOnly) {
                if response.name == "ditto" || response.name == "mew" {} else { XCTFail("Unexpected name") }; XCTAssertTrue(response.name == "ditto" || response.name == "mew")
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }

        XCTAssertEqual(resultsCount, 1, "A remoteOnly stream must yield exactly one result")
    }

    // MARK: - ETag with Custom Cache Tests

    /// Verifies that Harbor stores the response ETag when using the custom cache.
    func testCustomCacheStoresETag() async throws {
        let request = GetTestResourceCustomCacheETag()

        let response = await request.request()
        switch response {
        case .success(let user):
            if user.name == "ditto" || user.name == "mew" {} else { XCTFail("Unexpected user name") }; XCTAssertTrue(user.name == "ditto" || user.name == "mew")
        case .error(let err):
            XCTFail("Request failed: \(err)")
        }

        // The ETag must have been stored in the custom cache
        let storedETag = await request.cachedETag()
        XCTAssertNotNil(storedETag, "The custom cache must store the ETag received from the server")
        XCTAssertFalse(storedETag?.isEmpty ?? true, "The stored ETag must not be empty")
    }

    /// Verifies that Harbor sends If-None-Match on the second request and handles the 304:
    /// the server answers 304 and Harbor returns the custom-cache data transparently.
    func testCustomCacheETag304HandledTransparently() async throws {
        let request = GetTestResourceCustomCacheETag()

        // First request: fills the cache and stores the ETag
        let firstResponse = await request.request()
        switch firstResponse {
        case .success(let user):
            if user.name == "ditto" || user.name == "mew" {} else { XCTFail("Unexpected user name") }; XCTAssertTrue(user.name == "ditto" || user.name == "mew")
        case .error(let err):
            XCTFail("First request failed: \(err)")
        }

        // Verify that the ETag was stored
        let storedETag = await request.cachedETag()
        XCTAssertNotNil(storedETag, "An ETag must be stored before the second request")

        // Second request: Harbor attaches If-None-Match automatically.
        // The server answers 304 and Harbor returns the custom-cache data.
        let secondResponse = await request.request()
        switch secondResponse {
        case .success(let user):
            XCTAssertEqual(user.name, "ditto", "The second request (304 + custom cache) must return the same data")
        case .error(let err):
            XCTFail("Second request (expected 304 handled by custom cache) failed: \(err)")
        }
    }

    /// Waits until `urlCache` serves a cached response for `request`. URLCache persists
    /// responses asynchronously and exposes no completion barrier, so the wait polls
    /// `cachedResponse(for:)` until the entry is visible or `timeout` elapses.
    @discardableResult
    private func waitForCachedResponse<Request: HGetRequestProtocol>(of request: Request, in urlCache: URLCache, timeout: TimeInterval = 2) async -> Bool {
        guard let urlRequest = try? await HURLBuilder.buildUrlRequest(request: request) else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if urlCache.cachedResponse(for: urlRequest) != nil { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return urlCache.cachedResponse(for: urlRequest) != nil
    }
}
