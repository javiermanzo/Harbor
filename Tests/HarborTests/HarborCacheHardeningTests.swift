//
//  HarborCacheHardeningTests.swift
//  Harbor
//
//  Tests for the custom cache hardening: credential namespacing, hashed Vary keys,
//  decoding through parseData, clear/refresh races, freshness and memory limits.
//

import XCTest
@testable import Harbor

/// URLProtocol stub injected through `HConfig.protocolClasses`. Each request is answered by
/// the scripted handler, and every request is recorded.
private final class CacheStubProtocol: URLProtocol {
    /// One scripted reply.
    struct Reply: Sendable {
        var status: Int
        var headers: [String: String] = [:]
        var body: Data = Data()
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: (@Sendable (URLRequest) -> Reply)?
    nonisolated(unsafe) private static var _receivedRequests: [URLRequest] = []

    static var handler: (@Sendable (URLRequest) -> Reply)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _handler
        }
        set {
            lock.lock()
            _handler = newValue
            lock.unlock()
        }
    }

    static var receivedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _receivedRequests
    }

    static func reset() {
        lock.lock()
        _handler = nil
        _receivedRequests = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return request.url?.host == "cache-stub.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        Self.lock.lock()
        Self._receivedRequests.append(request)
        let handler = Self._handler
        Self.lock.unlock()

        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let reply = handler(request)
        guard let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty {
            client?.urlProtocol(self, didLoad: reply.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Auth provider that always issues the same credential.
@HRequestManagerActor
private final class FixedTokenProvider: HAuthProviderProtocol {
    private let token: String

    init(_ token: String) {
        self.token = token
    }

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        HAuthorizationHeader(key: "Authorization", value: token)
    }

    func authFailed() async {}
}

/// Request whose server wraps the model in a `{"data": ...}` envelope that `parseData` unwraps.
private struct EnvelopeRequest: HGetRequestProtocol {
    typealias Model = MockModel

    var url: String
    var cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneHour))

    private struct Envelope: Decodable {
        let data: MockModel
    }

    func parseData<T: Codable>(data: Data, model: T.Type) throws -> T {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let model = envelope.data as? T else {
            throw DecodingError.typeMismatch(T.self, .init(codingPath: [], debugDescription: "Unexpected model type"))
        }
        return model
    }
}

/// GET request with an explicit cache type, answered by the stub.
private struct CacheStubRequest: HGetRequestProtocol {
    typealias Model = MockModel

    var url: String
    var cacheType: HCache.CacheType?
    var needsAuth: Bool = false
}

@HRequestManagerActor
final class HarborCacheHardeningTests: XCTestCase {

    override func setUp() async throws {
        Harbor.removeAllMocks()
        Harbor.setAuthProvider(nil)
        HConfig.shared.customURLSession = nil
        Harbor.setProtocolClasses([CacheStubProtocol.self])
        Harbor.setDefaultCacheType(.custom(HCache.Configuration(expirationTime: .oneHour)))
        CacheStubProtocol.reset()
        await Harbor.clearAllCache()
    }

    override func tearDown() async throws {
        Harbor.setAuthProvider(nil)
        Harbor.setProtocolClasses(nil)
        Harbor.setDefaultCacheType(.urlCache())
        HRequestManager.connectivityMonitor = HRequestManagerMonitor()
        await Harbor.clearAllCache()
        CacheStubProtocol.reset()
    }

    // MARK: - Helpers

    nonisolated private static func body(_ quote: String) -> Data {
        Data("{\"quote\":\"\(quote)\"}".utf8)
    }

    nonisolated private static func envelope(_ quote: String) -> Data {
        Data("{\"data\":{\"quote\":\"\(quote)\"}}".utf8)
    }

    /// Formats a date as an IMF-fixdate HTTP header value.
    private static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    private func fileURL(forKey key: String) -> URL {
        HCache.Manager.shared.cacheDirectory.appendingPathComponent(key.sha256Hex).appendingPathExtension("cache")
    }

    /// Collects every element of a stream, returning the elements and the terminating error.
    private func collect(_ stream: AsyncThrowingStream<(response: MockModel, origin: HOriginType), Error>) async -> ([(String, HOriginType)], Error?) {
        var elements: [(String, HOriginType)] = []
        do {
            for try await (response, origin) in stream {
                elements.append((response.quote, origin))
            }
            return (elements, nil)
        } catch {
            return (elements, error)
        }
    }

    // MARK: - F2: Credential Namespacing

    func testSwitchingCredentialNeverServesAnotherAccountsCache() async throws {
        // Given a server that tags each body with the credential it was fetched with,
        // without Vary, and ALICE's response cached
        CacheStubProtocol.handler = { request in
            CacheStubProtocol.Reply(status: 200,
                                    headers: ["Cache-Control": "max-age=3600", "ETag": "\"etag\""],
                                    body: Self.body(request.value(forHTTPHeaderField: "Authorization") ?? "none"))
        }
        let request = CacheStubRequest(url: "https://cache-stub.test/me", needsAuth: true)

        Harbor.setAuthProvider(FixedTokenProvider("Bearer ALICE"))
        guard case .success(let alice) = await request.request() else {
            XCTFail("Expected ALICE's response")
            return
        }
        XCTAssertEqual(alice.quote, "Bearer ALICE")
        let aliceCached = await request.cache()
        XCTAssertEqual(aliceCached?.quote, "Bearer ALICE")

        // When the credential switches to BOB
        Harbor.setAuthProvider(FixedTokenProvider("Bearer BOB"))

        // Then cache() misses
        let bobCached = await request.cache()
        XCTAssertNil(bobCached, "BOB must never be served ALICE's cached body")

        // And .cacheOnly finds nothing
        let (cacheOnly, cacheOnlyError) = await collect(request.requestStream(source: .cacheOnly))
        XCTAssertTrue(cacheOnly.isEmpty)
        XCTAssertEqual(cacheOnlyError as? HRequestError, .noCachedDataFound)

        // And the offline fallback serves nothing
        HRequestManager.connectivityMonitor = FakeConnectivityMonitor(connected: false)
        let offline = await request.request()
        HRequestManager.connectivityMonitor = HRequestManagerMonitor()
        guard case .error(let offlineError) = offline else {
            XCTFail("Expected no offline content for BOB but got: \(offline)")
            return
        }
        XCTAssertEqual(offlineError, .noConnection)

        // And .cacheAndRemote only yields BOB's remote body, fetched without ALICE's validators
        let requestsBefore = CacheStubProtocol.receivedRequests.count
        let (cacheAndRemote, streamError) = await collect(request.requestStream(source: .cacheAndRemote))
        XCTAssertNil(streamError)
        XCTAssertEqual(cacheAndRemote.map(\.0), ["Bearer BOB"])
        XCTAssertEqual(cacheAndRemote.first?.1, .remote)
        let bobRequest = try XCTUnwrap(CacheStubProtocol.receivedRequests.dropFirst(requestsBefore).first)
        XCTAssertNil(bobRequest.value(forHTTPHeaderField: "If-None-Match"), "ALICE's validators must not be sent with BOB's credential")

        // And each credential keeps its own entry
        let bobAfter = await request.cache()
        XCTAssertEqual(bobAfter?.quote, "Bearer BOB")
        Harbor.setAuthProvider(FixedTokenProvider("Bearer ALICE"))
        let aliceAfter = await request.cache()
        XCTAssertEqual(aliceAfter?.quote, "Bearer ALICE")
    }

    func testCacheKeyIsNamespacedByAHashOfTheCredential() async throws {
        let url = try XCTUnwrap(URL(string: "https://cache-stub.test/me"))
        let alice = HAuthorizationHeader(key: "Authorization", value: "Bearer ALICE-SECRET")
        let bob = HAuthorizationHeader(key: "Authorization", value: "Bearer BOB-SECRET")

        let aliceKey = HCache.Manager.cacheKey(for: url, authHeader: alice)
        let bobKey = HCache.Manager.cacheKey(for: url, authHeader: bob)

        XCTAssertEqual(HCache.Manager.cacheKey(for: url, authHeader: nil), url.absoluteString)
        XCTAssertNotEqual(aliceKey, bobKey)
        XCTAssertEqual(aliceKey, HCache.Manager.cacheKey(for: url, authHeader: alice))
        XCTAssertFalse(aliceKey.contains("ALICE-SECRET"), "The raw credential must never be part of the key")
        XCTAssertTrue(aliceKey.hasPrefix(url.absoluteString))
    }

    func testRequestsWithoutAuthAreNotNamespaced() async throws {
        // Given a provider and a request that does not need auth
        Harbor.setAuthProvider(FixedTokenProvider("Bearer ALICE"))
        let request = CacheStubRequest(url: "https://cache-stub.test/public")
        let url = try XCTUnwrap(URL(string: request.url))
        await HCache.Manager.shared.storeData(Self.body("public"), forKey: url.absoluteString, config: HCache.Configuration(), response: nil)

        // Then the entry is shared regardless of the credential
        let cached = await request.cache()
        XCTAssertEqual(cached?.quote, "public")
    }

    // MARK: - F9: Hashed Vary Key

    func testVaryKeyNeverPersistsTheRawRequestHeaderValue() async throws {
        // Given an entry stored with Vary: Authorization
        let key = "https://cache-stub.test/vary-secret"
        let url = try XCTUnwrap(URL(string: key))
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Vary": "Authorization"])
        await HCache.Manager.shared.storeData(Self.body("v"), forKey: key, config: HCache.Configuration(), response: response, requestHeaders: ["Authorization": "Bearer SUPERSECRET-TOKEN"])
        await HCache.Manager.shared.waitForPendingDiskOperations()

        // Then the file on disk never contains the token
        let fileData = try Data(contentsOf: fileURL(forKey: key))
        XCTAssertNil(fileData.range(of: Data("SUPERSECRET-TOKEN".utf8)), "The raw credential must not be written to disk")
        let metadata = try XCTUnwrap(HCache.DiskCodec.decode(fileData)?.0)
        XCTAssertEqual(metadata.varyKey?.count, 64, "The vary key should be a SHA-256 hex digest")

        // And the vary matching still works
        let same: MockModel? = await HCache.Manager.shared.getCachedData(forKey: key, type: MockModel.self, config: HCache.Configuration(), requestHeaders: ["authorization": "Bearer SUPERSECRET-TOKEN"])
        let other: MockModel? = await HCache.Manager.shared.getCachedData(forKey: key, type: MockModel.self, config: HCache.Configuration(), requestHeaders: ["Authorization": "Bearer OTHER"])
        XCTAssertEqual(same?.quote, "v")
        XCTAssertNil(other)
    }

    // MARK: - F11: Decoding Through parseData

    func testCacheReadDecodesThroughParseData() async throws {
        // Given a server that wraps the model in an envelope
        CacheStubProtocol.handler = { _ in
            CacheStubProtocol.Reply(status: 200, headers: ["Cache-Control": "max-age=3600"], body: Self.envelope("wrapped"))
        }
        let request = EnvelopeRequest(url: "https://cache-stub.test/envelope")

        // When fetched
        guard case .success(let model) = await request.request() else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(model.quote, "wrapped")

        // Then the cache reads it back through parseData
        let cached = await request.cache()
        XCTAssertEqual(cached?.quote, "wrapped")
        let (stream, error) = await collect(request.requestStream(source: .cacheOnly))
        XCTAssertNil(error)
        XCTAssertEqual(stream.map(\.0), ["wrapped"])
    }

    func testNotModifiedServesTheCachedEnvelopeThroughParseData() async throws {
        // Given an expired entry with a validator and a server answering 304 to conditional requests
        CacheStubProtocol.handler = { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"" {
                return CacheStubProtocol.Reply(status: 304, headers: ["Cache-Control": "max-age=3600"])
            }
            return CacheStubProtocol.Reply(status: 200, headers: ["Cache-Control": "max-age=0", "ETag": "\"v1\""], body: Self.envelope("first"))
        }
        let request = EnvelopeRequest(url: "https://cache-stub.test/envelope-304")
        _ = await request.request()

        // When revalidated
        let response = await request.request()

        // Then the 304 is satisfied with the cached body instead of failing with .api(304)
        guard case .success(let model) = response else {
            XCTFail("Expected the cached body but got: \(response)")
            return
        }
        XCTAssertEqual(model.quote, "first")
        XCTAssertEqual(CacheStubProtocol.receivedRequests.count, 2)
        XCTAssertEqual(CacheStubProtocol.receivedRequests.last?.value(forHTTPHeaderField: "If-None-Match"), "\"v1\"")
    }

    func testNotModifiedWithUndecodableCachedBodyRefetchesUnconditionally() async throws {
        // Given a stored entry with a validator whose body the request cannot decode anymore
        let request = EnvelopeRequest(url: "https://cache-stub.test/envelope-stale-format")
        let url = try XCTUnwrap(URL(string: request.url))
        let storeResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "max-age=0", "ETag": "\"old\""])
        await request.saveCache(Data("{\"legacy\":true}".utf8), response: storeResponse, authHeader: nil)

        CacheStubProtocol.handler = { request in
            if request.value(forHTTPHeaderField: "If-None-Match") != nil {
                return CacheStubProtocol.Reply(status: 304)
            }
            return CacheStubProtocol.Reply(status: 200, headers: ["Cache-Control": "max-age=3600"], body: Self.envelope("fresh"))
        }

        // When
        let response = await request.request()

        // Then the request is re-issued unconditionally and its body replaces the entry
        guard case .success(let model) = response else {
            XCTFail("Expected the refetched body but got: \(response)")
            return
        }
        XCTAssertEqual(model.quote, "fresh")
        let received = CacheStubProtocol.receivedRequests
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.first?.value(forHTTPHeaderField: "If-None-Match"), "\"old\"")
        XCTAssertNil(received.last?.value(forHTTPHeaderField: "If-None-Match"))

        // And the next request does not loop on the stale validator
        let cached = await request.cache()
        XCTAssertEqual(cached?.quote, "fresh")
    }

    func testUndecodableCachedBodyIsAMissButIsNotEvicted() async throws {
        // Given an entry stored by a request type that decodes the body as is
        let url = "https://cache-stub.test/shared-url"
        let plain = CacheStubRequest(url: url, cacheType: .custom(HCache.Configuration(expirationTime: .oneHour)))
        await plain.saveCache(Self.body("plain"), response: nil, authHeader: nil)
        await HCache.Manager.shared.waitForPendingDiskOperations()
        let key = try XCTUnwrap(URL(string: url)).absoluteString
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL(forKey: key).path))

        // When another request type sharing the URL cannot decode it
        let cached = await EnvelopeRequest(url: url).cache()

        // Then it is a miss for that type only: the entry is kept for the type that stored it
        XCTAssertNil(cached)
        await HCache.Manager.shared.waitForPendingDiskOperations()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL(forKey: key).path))
        let plainCached = await plain.cache()
        XCTAssertEqual(plainCached?.quote, "plain")
    }

    func testUndecodableDiskEntryIsAMissButIsNotEvicted() async throws {
        // Given an entry only on disk (memory dropped), stored by a type that decodes it
        let url = "https://cache-stub.test/shared-url-disk"
        let plain = CacheStubRequest(url: url, cacheType: .custom(HCache.Configuration(expirationTime: .oneHour)))
        await plain.saveCache(Self.body("plain"), response: nil, authHeader: nil)
        await HCache.Manager.shared.waitForPendingDiskOperations()
        HCache.Manager.shared.simulateRelaunch()

        // When another request type sharing the URL reads it
        let cached = await EnvelopeRequest(url: url).cache()

        // Then it is a miss, and the entry survives for the type that stored it
        XCTAssertNil(cached)
        let plainCached = await plain.cache()
        XCTAssertEqual(plainCached?.quote, "plain")
    }

    // MARK: - Access-Time Persistence

    func testMemoryHitsDoNotTouchTheDiskBeforeTheIndexExists() async throws {
        // Given a stored entry, read back after a relaunch (no memory, no disk index yet)
        let request = CacheStubRequest(url: "https://cache-stub.test/touch-throttle", cacheType: .custom(HCache.Configuration(expirationTime: .oneHour)))
        await request.saveCache(Self.body("touch"), response: nil, authHeader: nil)
        await HCache.Manager.shared.waitForPendingDiskOperations()
        HCache.Manager.shared.simulateRelaunch()
        let touchesBefore = HCache.Manager.shared.diskAccessTouchCount

        // When it is read many times (one disk read, then memory hits)
        for _ in 0 ..< 20 {
            let cached = await request.cache()
            XCTAssertEqual(cached?.quote, "touch")
        }

        // Then the on-disk access time is persisted once, not once per hit
        XCTAssertEqual(HCache.Manager.shared.diskAccessTouchCount - touchesBefore, 1)
    }

    func testURLCacheReadDecodesThroughParseData() async throws {
        // Given a fresh envelope stored in a dedicated URLCache
        let urlCache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0)
        let request = EnvelopeRequest(url: "https://cache-stub.test/url-cache-envelope", cacheType: .urlCache(urlCache: urlCache))
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
        let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(urlRequest.url), statusCode: 200, httpVersion: "HTTP/1.1",
                                                     headerFields: ["Cache-Control": "max-age=600", "Date": Self.httpDate(Date())]))
        urlCache.storeCachedResponse(CachedURLResponse(response: response, data: Self.envelope("url-wrapped")), for: urlRequest)

        // Then
        let cached = await request.cache()
        XCTAssertEqual(cached?.quote, "url-wrapped")
    }

    // MARK: - F20: Clear Races And no-store

    func testNoStoreResponseEvictsThePreviousEntry() async throws {
        // Given a cached entry
        let key = "https://cache-stub.test/no-store"
        let url = try XCTUnwrap(URL(string: key))
        await HCache.Manager.shared.storeData(Self.body("old"), forKey: key, config: HCache.Configuration(), response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "\"old\""]))

        // When a no-store response arrives for the same key
        let noStore = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "no-store"])
        await HCache.Manager.shared.storeData(Self.body("new"), forKey: key, config: HCache.Configuration(), response: noStore)
        await HCache.Manager.shared.waitForPendingDiskOperations()

        // Then the previous entry is no longer served nor used for validation
        let cached: MockModel? = await HCache.Manager.shared.getCachedData(forKey: key, type: MockModel.self, config: HCache.Configuration())
        XCTAssertNil(cached)
        let etag = await HCache.Manager.shared.getETag(forKey: key)
        XCTAssertNil(etag)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL(forKey: key).path))
    }

    func testRefreshEntryNeverUndoesAConcurrentClear() async throws {
        let config = HCache.Configuration()
        for index in 0 ..< 30 {
            // Given an entry only on disk (as after a relaunch)
            let key = "https://cache-stub.test/refresh-race-\(index)"
            var metadata = HCache.EntryMetadata(timestamp: Date(), expirationTime: 0)
            metadata.etag = "\"race\""
            try HCache.DiskCodec.encode(metadata, body: Self.body("race")).write(to: fileURL(forKey: key))
            let url = try XCTUnwrap(URL(string: key))
            let notModified = HTTPURLResponse(url: url, statusCode: 304, httpVersion: nil, headerFields: ["Cache-Control": "max-age=3600"])

            // When a 304 refresh and a clear run concurrently
            async let refresh: Void = HCache.Manager.shared.refreshEntry(forKey: key, response: notModified, config: config)
            async let clear: Void = HCache.Manager.shared.clearAllCache()
            _ = await (refresh, clear)
            await HCache.Manager.shared.waitForPendingDiskOperations()

            // Then whatever the interleaving, the cleared entry never comes back
            let cached: MockModel? = await HCache.Manager.shared.getCachedData(forKey: key, type: MockModel.self, config: config)
            XCTAssertNil(cached, "Iteration \(index): a refresh must not resurrect a cleared entry")
            XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL(forKey: key).path), "Iteration \(index)")
        }
    }

    func testDiskReadNeverPromotesAnEntryClearedConcurrently() async throws {
        let config = HCache.Configuration()
        for index in 0 ..< 30 {
            // Given a fresh entry only on disk
            let key = "https://cache-stub.test/promote-race-\(index)"
            try HCache.DiskCodec.encode(HCache.EntryMetadata(timestamp: Date(), expirationTime: 3600), body: Self.body("race")).write(to: fileURL(forKey: key))

            // When a read and a clear run concurrently
            async let read: MockModel? = HCache.Manager.shared.getCachedData(forKey: key, type: MockModel.self, config: config)
            async let clear: Void = HCache.Manager.shared.clearAllCache()
            _ = await (read, clear)

            // Then the entry is not left in memory
            let cached: MockModel? = await HCache.Manager.shared.getCachedData(forKey: key, type: MockModel.self, config: config)
            XCTAssertNil(cached, "Iteration \(index): a read must not promote a cleared entry back into memory")
        }
    }

    // MARK: - F21: Freshness

    func testAgeHeaderReducesTheFreshnessLifetime() async throws {
        let url = try XCTUnwrap(URL(string: "https://cache-stub.test/age"))
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "max-age=600", "Age": "590"])
        XCTAssertEqual(HCache.Manager.shared.calculateEffectiveExpirationTime(fromResponse: response, fallbackTime: nil), 10)

        let older = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "max-age=600", "Age": "900"])
        XCTAssertEqual(HCache.Manager.shared.calculateEffectiveExpirationTime(fromResponse: older, fallbackTime: nil), 0)
    }

    func testExpiresIsMeasuredFromTheResponseDate() async throws {
        // Given a server whose clock is a day behind the local one
        let serverNow = Date().addingTimeInterval(-86_400)
        let url = try XCTUnwrap(URL(string: "https://cache-stub.test/expires"))
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
            "Date": Self.httpDate(serverNow),
            "Expires": Self.httpDate(serverNow.addingTimeInterval(3600))
        ])

        // Then the lifetime is the server-side difference, not "already expired"
        let lifetime = try XCTUnwrap(HCache.Manager.shared.calculateEffectiveExpirationTime(fromResponse: response, fallbackTime: nil))
        XCTAssertEqual(lifetime, 3600, accuracy: 1)
    }

    func testStaleWhileRevalidateServesFromCacheAndStillRevalidates() async throws {
        // Given a response that is immediately stale but within its stale-while-revalidate window
        CacheStubProtocol.handler = { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"swr\"" {
                return CacheStubProtocol.Reply(status: 304, headers: ["Cache-Control": "max-age=0, stale-while-revalidate=300"])
            }
            return CacheStubProtocol.Reply(status: 200, headers: ["Cache-Control": "max-age=0, stale-while-revalidate=300", "ETag": "\"swr\""], body: Self.body("swr"))
        }
        let request = CacheStubRequest(url: "https://cache-stub.test/swr")
        _ = await request.request()

        // Then cache() serves it
        let cached = await request.cache()
        XCTAssertEqual(cached?.quote, "swr")

        // And .cacheAndRemote yields it from cache and revalidates remotely
        let (elements, error) = await collect(request.requestStream(source: .cacheAndRemote))
        XCTAssertNil(error)
        XCTAssertEqual(elements.map(\.1), [.cache, .remote])
        XCTAssertEqual(CacheStubProtocol.receivedRequests.last?.value(forHTTPHeaderField: "If-None-Match"), "\"swr\"")
    }

    func testStaleWhileRevalidateIsIgnoredWhenRevalidationIsMandatory() async throws {
        let key = "https://cache-stub.test/swr-must-revalidate"
        let url = try XCTUnwrap(URL(string: key))
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "max-age=0, stale-while-revalidate=300, must-revalidate"])
        await HCache.Manager.shared.storeData(Self.body("x"), forKey: key, config: HCache.Configuration(), response: response)

        let cached: MockModel? = await HCache.Manager.shared.getCachedData(forKey: key, type: MockModel.self, config: HCache.Configuration())
        XCTAssertNil(cached)
    }

    func testURLCacheReadRespectsFreshness() async throws {
        let urlCache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0)
        let request = CacheStubRequest(url: "https://cache-stub.test/url-cache-fresh", cacheType: .urlCache(urlCache: urlCache))
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
        let url = try XCTUnwrap(urlRequest.url)

        func store(_ headers: [String: String]) throws {
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers))
            urlCache.storeCachedResponse(CachedURLResponse(response: response, data: Self.body("url")), for: urlRequest)
        }
        let now = Date()

        // Fresh
        try store(["Cache-Control": "max-age=600", "Date": Self.httpDate(now)])
        var cached = await request.cache()
        XCTAssertEqual(cached?.quote, "url")

        // Expired by age
        try store(["Cache-Control": "max-age=60", "Date": Self.httpDate(now.addingTimeInterval(-120))])
        cached = await request.cache()
        XCTAssertNil(cached, "Expired URLCache entries must not be served")

        // Expired through the Age header
        try store(["Cache-Control": "max-age=600", "Age": "600", "Date": Self.httpDate(now)])
        cached = await request.cache()
        XCTAssertNil(cached)

        // Within stale-while-revalidate
        try store(["Cache-Control": "max-age=60, stale-while-revalidate=300", "Date": Self.httpDate(now.addingTimeInterval(-120))])
        cached = await request.cache()
        XCTAssertEqual(cached?.quote, "url")

        // No freshness information: served as stored (URLCache itself decided to keep it)
        try store(["ETag": "\"only-etag\""])
        cached = await request.cache()
        XCTAssertEqual(cached?.quote, "url", "A stored response without freshness information is servable")

        // A plain 200 with only Content-Type and Date is served
        try store(["Content-Type": "application/json", "Date": Self.httpDate(now)])
        cached = await request.cache()
        XCTAssertEqual(cached?.quote, "url")

        // max-age without a Date header cannot be aged: served while the Age header stays within it
        try store(["Cache-Control": "max-age=600"])
        cached = await request.cache()
        XCTAssertEqual(cached?.quote, "url")

        // ...but an explicitly stale lifetime is honored even without a Date header
        try store(["Cache-Control": "max-age=0"])
        cached = await request.cache()
        XCTAssertNil(cached)
        try store(["Cache-Control": "max-age=600", "Age": "900"])
        cached = await request.cache()
        XCTAssertNil(cached)

        // Expires in the past
        try store(["Expires": Self.httpDate(now.addingTimeInterval(-60)), "Date": Self.httpDate(now.addingTimeInterval(-120))])
        cached = await request.cache()
        XCTAssertNil(cached)

        // Last-Modified heuristic (10% of the age at Date): still fresh
        try store(["Date": Self.httpDate(now), "Last-Modified": Self.httpDate(now.addingTimeInterval(-10 * 86_400))])
        cached = await request.cache()
        XCTAssertEqual(cached?.quote, "url")

        // Last-Modified heuristic elapsed: 10% of one hour is 6 minutes, the response is an hour old
        try store(["Date": Self.httpDate(now.addingTimeInterval(-3600)), "Last-Modified": Self.httpDate(now.addingTimeInterval(-7200))])
        cached = await request.cache()
        XCTAssertNil(cached)

        // Last-Modified without Date cannot be aged: served
        try store(["Last-Modified": Self.httpDate(now.addingTimeInterval(-7200))])
        cached = await request.cache()
        XCTAssertEqual(cached?.quote, "url")

        // no-cache
        try store(["Cache-Control": "no-cache, max-age=600", "Date": Self.httpDate(now)])
        cached = await request.cache()
        XCTAssertNil(cached)

        // no-store
        try store(["Cache-Control": "no-store", "Date": Self.httpDate(now)])
        cached = await request.cache()
        XCTAssertNil(cached)
    }

    func testURLCacheReadHonorsPoliciesPreferringCachedData() async throws {
        let urlCache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0)
        let request = CacheStubRequest(url: "https://cache-stub.test/url-cache-prefer", cacheType: .urlCache(urlCache: urlCache, requestCachePolicy: .returnCacheDataElseLoad))
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
        let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(urlRequest.url), statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["ETag": "\"only-etag\""]))
        urlCache.storeCachedResponse(CachedURLResponse(response: response, data: Self.body("preferred")), for: urlRequest)

        let cached = await request.cache()
        XCTAssertEqual(cached?.quote, "preferred")
    }

    // MARK: - F32: Memory Limits

    func testMemoryLimitFollowsTheDefaultConfigurationAndNeverShrinksPerRequest() async {
        // Given a global default with 50 MB of memory
        Harbor.setDefaultCacheType(.custom(HCache.Configuration(memoryCacheCapacityInMBs: 50)))
        XCTAssertEqual(HCache.Manager.shared.memoryCacheCostLimit, 50 * 1024 * 1024)
        XCTAssertEqual(HCache.Manager.shared.memoryCacheCountLimit, 0, "The memory cache should be bounded by cost, not by a fixed count")

        // When a request stores with a smaller configuration, the limit is kept
        await HCache.Manager.shared.storeData(Self.body("small"), forKey: "https://cache-stub.test/mem-small", config: HCache.Configuration(memoryCacheCapacityInMBs: 2), response: nil)
        XCTAssertEqual(HCache.Manager.shared.memoryCacheCostLimit, 50 * 1024 * 1024)

        // And a larger one raises it
        await HCache.Manager.shared.storeData(Self.body("large"), forKey: "https://cache-stub.test/mem-large", config: HCache.Configuration(memoryCacheCapacityInMBs: 200), response: nil)
        XCTAssertEqual(HCache.Manager.shared.memoryCacheCostLimit, 200 * 1024 * 1024)

        // And a later smaller one does not lower it back (no last-writer-wins)
        await HCache.Manager.shared.storeData(Self.body("small"), forKey: "https://cache-stub.test/mem-small-2", config: HCache.Configuration(memoryCacheCapacityInMBs: 2), response: nil)
        XCTAssertEqual(HCache.Manager.shared.memoryCacheCostLimit, 200 * 1024 * 1024)

        // When the default changes, the limit is derived from it again
        Harbor.setDefaultCacheType(.custom(HCache.Configuration(memoryCacheCapacityInMBs: 10)))
        XCTAssertEqual(HCache.Manager.shared.memoryCacheCostLimit, 10 * 1024 * 1024)
    }

    // MARK: - Review Follow-ups

    func testExpiredStaleIfErrorEntryWithoutValidatorIsKeptForErrors() async throws {
        // Given an expired entry without validators, still inside its stale-if-error window
        let key = "https://cache-stub.test/stale-if-error-kept"
        let metadata = HCache.EntryMetadata(timestamp: Date().addingTimeInterval(-120), expirationTime: 60, staleIfError: 86_400)
        try HCache.DiskCodec.encode(metadata, body: Self.body("stale")).write(to: fileURL(forKey: key))

        // When a regular read misses it
        let fresh: MockModel? = await HCache.Manager.shared.getCachedData(forKey: key, type: MockModel.self, config: HCache.Configuration())
        XCTAssertNil(fresh)

        // Then it is not evicted and can still be served on error
        let stale: MockModel? = await HCache.Manager.shared.getStaleOnErrorData(forKey: key, type: MockModel.self)
        XCTAssertEqual(stale?.quote, "stale")
        XCTAssertFalse(metadata.isDiscardable(maxAge: nil))
    }

    func testExpiredEntryWithoutValidatorOrStaleWindowIsDiscardable() async {
        let metadata = HCache.EntryMetadata(timestamp: Date().addingTimeInterval(-120), expirationTime: 60)
        XCTAssertTrue(metadata.isDiscardable(maxAge: nil))

        let outsideWindow = HCache.EntryMetadata(timestamp: Date().addingTimeInterval(-600), expirationTime: 60, staleIfError: 60)
        XCTAssertTrue(outsideWindow.isDiscardable(maxAge: nil))

        let mustRevalidate = HCache.EntryMetadata(timestamp: Date().addingTimeInterval(-120), expirationTime: 60, mustRevalidate: true, staleIfError: 86_400)
        XCTAssertTrue(mustRevalidate.isDiscardable(maxAge: nil))
    }

    func testSharedCacheDirectivesAreIgnored() async throws {
        // s-maxage and proxy-revalidate only apply to shared caches (RFC 9111)
        let url = try XCTUnwrap(URL(string: "https://cache-stub.test/s-maxage"))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "max-age=0, s-maxage=600"]))

        XCTAssertEqual(HCache.Manager.shared.calculateEffectiveExpirationTime(fromResponse: response, fallbackTime: nil), 0)
        XCTAssertFalse(HCache.Manager.isFresh(urlCacheResponse: response))
    }

    func testNeedsAuthResponseSentWithoutCredentialIsNotCached() async throws {
        // Given a provider without credentials, so the request is sent without a header
        CacheStubProtocol.handler = { _ in
            CacheStubProtocol.Reply(status: 200, headers: ["Cache-Control": "max-age=3600"], body: Self.body("anonymous"))
        }
        Harbor.setAuthProvider(NoCredentialProvider())
        let request = CacheStubRequest(url: "https://cache-stub.test/anonymous", needsAuth: true)

        guard case .success = await request.request() else {
            return XCTFail("Expected the request to succeed without credentials")
        }

        // Then nothing is cached, neither namespaced nor under the plain URL
        let plain: MockModel? = await HCache.Manager.shared.getCachedData(forKey: request.url, type: MockModel.self, config: HCache.Configuration())
        XCTAssertNil(plain)

        // And a credential issued later never sees the anonymous body
        Harbor.setAuthProvider(FixedTokenProvider("Bearer LATER"))
        let cached = await request.cache()
        XCTAssertNil(cached)
    }

    func testClearAllCacheDuringAnInFlightRequestDiscardsItsResponse() async throws {
        // Given a slow response for an authenticated request
        CacheStubProtocol.handler = { _ in
            Thread.sleep(forTimeInterval: 0.4)
            return CacheStubProtocol.Reply(status: 200, headers: ["Cache-Control": "max-age=3600"], body: Self.body("previous-user"))
        }
        Harbor.setAuthProvider(FixedTokenProvider("Bearer ALICE"))
        let request = CacheStubRequest(url: "https://cache-stub.test/logout-race", needsAuth: true)

        // When the cache is cleared (logout) while it is in flight
        let inFlight = Task { await request.request() }
        try await Task.sleep(nanoseconds: 100_000_000)
        await Harbor.clearAllCache()
        let response = await inFlight.value

        // Then the caller still gets the response, but it is not written back to the cache
        guard case .success(let model) = response else {
            return XCTFail("Expected the in-flight request to succeed but got: \(response)")
        }
        XCTAssertEqual(model.quote, "previous-user")
        let cached = await request.cache()
        XCTAssertNil(cached, "A response started before clearAllCache() must not repopulate the cache")
    }
}

/// Auth provider that has no credentials.
private final class NoCredentialProvider: HAuthProviderProtocol {
    func getAuthorizationHeader() async -> HAuthorizationHeader? { nil }
    func authFailed() async {}
}
