//
//  HarborConnectivityTests.swift
//  Harbor
//
//  Tests for the network connectivity pre-check (NWPathMonitor based).
//

import XCTest
import Network
@testable import Harbor

@HRequestManagerActor
final class HarborConnectivityTests: XCTestCase {

    // MARK: - shouldAllowRequest decision logic

    func testShouldAllowRequestBeforeInitialUpdate() async {
        // Given the monitor has not delivered its first path update yet (status unknown),
        // requests must proceed optimistically even without the debug fallback.
        // Regression test: previously the first request after launch was rejected
        // with .noConnection in Release builds.
        let allowed = HRequestManagerMonitor.shouldAllowRequest(hasReceivedInitialUpdate: false,
                                                         pathStatus: .unsatisfied,
                                                         allowsDebugFallback: false)

        XCTAssertTrue(allowed)
    }

    func testShouldAllowRequestWhenPathIsSatisfied() async {
        let allowed = HRequestManagerMonitor.shouldAllowRequest(hasReceivedInitialUpdate: true,
                                                         pathStatus: .satisfied,
                                                         allowsDebugFallback: false)

        XCTAssertTrue(allowed)
    }

    func testShouldBlockRequestWhenOfflineInRelease() async {
        // Given a real offline reading after the initial update,
        // requests must still be blocked when there is no debug fallback (Release).
        let allowed = HRequestManagerMonitor.shouldAllowRequest(hasReceivedInitialUpdate: true,
                                                         pathStatus: .unsatisfied,
                                                         allowsDebugFallback: false)

        XCTAssertFalse(allowed)
    }

    func testShouldAllowRequestWhenOfflineWithDebugFallback() async {
        // Given a real offline reading, DEBUG/simulator builds keep the permissive fallback.
        let allowed = HRequestManagerMonitor.shouldAllowRequest(hasReceivedInitialUpdate: true,
                                                         pathStatus: .unsatisfied,
                                                         allowsDebugFallback: true)

        XCTAssertTrue(allowed)
    }

    func testShouldAllowRequestWhenRequiresConnectionInRelease() async {
        // .requiresConnection means a connection can be established on demand (VPN on demand,
        // cellular waking up); the request itself triggers it, so it must not be blocked.
        let allowed = HRequestManagerMonitor.shouldAllowRequest(hasReceivedInitialUpdate: true,
                                                         pathStatus: .requiresConnection,
                                                         allowsDebugFallback: false)

        XCTAssertTrue(allowed)
    }

    // MARK: - Integration

    func testIsConnectedToNetworkReturnsTrueInDebug() async {
        // In DEBUG the check always allows requests (fallback), starting the monitor lazily.
        XCTAssertTrue(HRequestManager.connectivityMonitor.isConnectedToNetwork())
    }

    func testStartNetworkMonitorIsIdempotent() async {
        // Starting the monitor multiple times must be safe.
        HRequestManager.connectivityMonitor.start()
        HRequestManager.connectivityMonitor.start()

        XCTAssertTrue(HRequestManager.connectivityMonitor.isConnectedToNetwork())
    }

    func testStopNetworkMonitorAllowsRestart() async {
        // Stopping the monitor must leave it in a state where the next check starts it fresh.
        HRequestManager.connectivityMonitor = HRequestManagerMonitor()
        HRequestManager.connectivityMonitor.start()

        await Harbor.stopNetworkMonitor()

        XCTAssertTrue(HRequestManager.connectivityMonitor.isConnectedToNetwork())
    }

    func testRequestFailsWithNoConnectionWhenMonitorReportsOffline() async {
        // Given a fake monitor that reports offline (bypasses the DEBUG fallback),
        // the request pipeline must short-circuit with .noConnection without hitting the network.
        HRequestManager.connectivityMonitor = FakeConnectivityMonitor(connected: false)
        defer { HRequestManager.connectivityMonitor = HRequestManagerMonitor() }

        await Harbor.removeAllMocks()
        let response = await MockGetRequest<MockModel>(url: "https://example.com/users").request()

        guard case .error(let error) = response, case .noConnection = error else {
            XCTFail("Expected .noConnection but got: \(response)")
            return
        }
    }
}

// MARK: - Offline Cache Fallback

@HRequestManagerActor
final class HarborOfflineCacheFallbackTests: XCTestCase {

    override func setUp() async throws {
        Harbor.removeAllMocks()
        Harbor.setAuthProvider(nil)
        HConfig.shared.customURLSession = nil
        await Harbor.clearAllCache()
    }

    override func tearDown() async throws {
        HRequestManager.connectivityMonitor = HRequestManagerMonitor()
        Harbor.setProtocolClasses(nil)
        HConfig.shared.customURLSession = nil
        await Harbor.clearAllCache()
    }

    func testFreshCustomCacheEntryIsServedWhenMonitorReportsOffline() async throws {
        // Given a still-fresh custom-cache entry (no stale-if-error) and an offline monitor
        let request = OfflineGetRequest(url: "https://example.com/offline-fresh", cacheType: .custom(HCache.Configuration(expirationTime: .oneHour)))
        try await storeCustomEntry(#"{"quote":"fresh"}"#, for: request, cacheControl: "max-age=3600")
        HRequestManager.connectivityMonitor = FakeConnectivityMonitor(connected: false)

        // When
        let response = await request.request()

        // Then the fresh entry is served instead of failing with .noConnection
        guard case .success(let model) = response else {
            return XCTFail("Expected the cached body but got: \(response)")
        }
        XCTAssertEqual(model.quote, "fresh")
    }

    func testStreamTagsACachedCopyThatStoodInForTheNetworkAsCache() async throws {
        // Given a fresh custom-cache entry and an offline monitor
        let request = OfflineGetRequest(url: "https://example.com/offline-stream", cacheType: .custom(HCache.Configuration(expirationTime: .oneHour)))
        try await storeCustomEntry(#"{"quote":"offline"}"#, for: request, cacheControl: "max-age=3600")
        HRequestManager.connectivityMonitor = FakeConnectivityMonitor(connected: false)

        // When the request is read with the network as its only source
        var remoteOnly: [(MockModel, HOriginType)] = []
        for try await element in request.requestStream(source: .remoteOnly) { remoteOnly.append((element.response, element.origin)) }

        // Then the copy is the device's, not the server's word
        XCTAssertEqual(remoteOnly.map(\.0.quote), ["offline"])
        XCTAssertEqual(remoteOnly.map(\.1), [.cache])

        // And cache-then-network yields that one copy once, as cache (not again as if the server had answered)
        var both: [(MockModel, HOriginType)] = []
        for try await element in request.requestStream(source: .cacheAndRemote) { both.append((element.response, element.origin)) }
        XCTAssertEqual(both.map(\.1), [.cache])
    }

    func testStreamTagsAStaleCopyServedAfterAServerErrorAsCache() async throws {
        // Given an expired entry that stale-if-error still allows, and a server answering 503
        let request = OfflineGetRequest(url: "https://example.com/stale-stream", cacheType: .custom(HCache.Configuration(expirationTime: .oneHour)))
        try await storeCustomEntry(#"{"quote":"stale"}"#, for: request, cacheControl: "max-age=0, stale-if-error=3600")
        Harbor.setMocksEnabled(true)
        Harbor.register(mock: HMock(request: OfflineGetRequest.self, statusCode: 503, jsonResponse: "{}"))
        defer { Harbor.setMocksEnabled(false) }

        var elements: [(MockModel, HOriginType)] = []
        for try await element in request.requestStream(source: .remoteOnly) { elements.append((element.response, element.origin)) }

        XCTAssertEqual(elements.map(\.0.quote), ["stale"])
        XCTAssertEqual(elements.map(\.1), [.cache])
    }

    func testStreamTagsARealNetworkAnswerAsRemote() async throws {
        Harbor.setMocksEnabled(true)
        Harbor.register(mock: HMock(request: OfflineGetRequest.self, statusCode: 200, jsonResponse: #"{"quote":"live"}"#))
        defer { Harbor.setMocksEnabled(false) }
        let request = OfflineGetRequest(url: "https://example.com/live-stream", cacheType: .disabled)

        var elements: [(MockModel, HOriginType)] = []
        for try await element in request.requestStream() { elements.append((element.response, element.origin)) }

        XCTAssertEqual(elements.map(\.0.quote), ["live"])
        XCTAssertEqual(elements.map(\.1), [.remote])
    }

    func testAResponseTheRequestRefusesToCacheDoesNotReplaceTheStoredCopy() async throws {
        // Given a good stored copy, and a request that does not cache 202 answers
        let request = NoAcceptedCacheRequest(url: "https://example.com/accepted", cacheType: .custom(HCache.Configuration(expirationTime: .oneHour)))
        try await storeCustomEntry(#"{"quote":"good"}"#, for: request.asOffline, cacheControl: "max-age=0, stale-if-error=3600")
        Harbor.setMocksEnabled(true)
        Harbor.register(mock: HMock(request: NoAcceptedCacheRequest.self, statusCode: 202, jsonResponse: #"{"quote":"preparing"}"#))
        defer { Harbor.setMocksEnabled(false) }

        // When the server answers 202
        guard case .success(let accepted) = await request.request() else { return XCTFail("expected the 202 body") }
        XCTAssertEqual(accepted.quote, "preparing")
        Harbor.removeAllMocks()

        // Then the stored copy is still the good one
        let stored = await request.offlineCache(authHeader: nil, resolvingAuthHeader: false) as? MockModel
        XCTAssertEqual(stored?.quote, "good")
    }

    func testURLCacheResponseIsServedWhenMonitorReportsOffline() async throws {
        // Given a response stored in the request's URLCache and an offline monitor
        let urlCache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0)
        let request = OfflineGetRequest(url: "https://example.com/offline-url-cache", cacheType: .urlCache(urlCache: urlCache))
        try await storeURLCacheResponse(#"{"quote":"url-cache"}"#, for: request, in: urlCache)
        HRequestManager.connectivityMonitor = FakeConnectivityMonitor(connected: false)

        // When
        let response = await request.request()

        // Then
        guard case .success(let model) = response else {
            return XCTFail("Expected the URLCache body but got: \(response)")
        }
        XCTAssertEqual(model.quote, "url-cache")
    }

    func testURLCacheIgnoringLocalDataIsNotServedOffline() async throws {
        // Given a stored response but a policy that ignores local data
        let urlCache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0)
        let request = OfflineGetRequest(url: "https://example.com/offline-reload", cacheType: .urlCache(urlCache: urlCache, requestCachePolicy: .reloadIgnoringLocalCacheData))
        try await storeURLCacheResponse(#"{"quote":"url-cache"}"#, for: request, in: urlCache)
        HRequestManager.connectivityMonitor = FakeConnectivityMonitor(connected: false)

        // When
        let response = await request.request()

        // Then
        guard case .error(.noConnection) = response else {
            return XCTFail("Expected .noConnection but got: \(response)")
        }
    }

    func testFreshCustomCacheEntryIsServedOnNotConnectedURLError() async throws {
        // Given the monitor reports online but the transport fails with no connectivity
        let request = OfflineGetRequest(url: "https://example.com/transport-offline", cacheType: .custom(HCache.Configuration(expirationTime: .oneHour)))
        try await storeCustomEntry(#"{"quote":"fresh"}"#, for: request, cacheControl: "max-age=3600")
        HRequestManager.connectivityMonitor = FakeConnectivityMonitor(connected: true)
        Harbor.setProtocolClasses([NotConnectedStubProtocol.self])

        // When
        let response = await request.request()

        // Then
        guard case .success(let model) = response else {
            return XCTFail("Expected the cached body but got: \(response)")
        }
        XCTAssertEqual(model.quote, "fresh")
    }

    func testNotConnectedURLErrorWithoutCacheFailsWithNoConnection() async throws {
        // Given no cached entry and a transport without connectivity
        let request = OfflineGetRequest(url: "https://example.com/transport-offline-miss", cacheType: .custom(HCache.Configuration(expirationTime: .oneHour)))
        HRequestManager.connectivityMonitor = FakeConnectivityMonitor(connected: true)
        Harbor.setProtocolClasses([NotConnectedStubProtocol.self])

        // When
        let response = await request.request()

        // Then
        guard case .error(.noConnection) = response else {
            return XCTFail("Expected .noConnection but got: \(response)")
        }
    }

    // MARK: - Helpers

    private func storeCustomEntry(_ body: String, for request: OfflineGetRequest, cacheControl: String) async throws {
        let url = try XCTUnwrap(URL(string: request.url))
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": cacheControl])
        await request.saveCache(Data(body.utf8), response: response, authHeader: nil)
    }

    private func storeURLCacheResponse(_ body: String, for request: OfflineGetRequest, in urlCache: URLCache) async throws {
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
        let url = try XCTUnwrap(urlRequest.url)
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "max-age=60"]))
        urlCache.storeCachedResponse(CachedURLResponse(response: response, data: Data(body.utf8)), for: urlRequest)
    }
}

/// A request that does not cache `202 Accepted` answers (the resource is still being prepared).
private struct NoAcceptedCacheRequest: HGetRequestProtocol {
    typealias Model = MockModel
    var url: String
    var cacheType: HCache.CacheType?
    func shouldCache(statusCode: Int) -> Bool { statusCode != 202 }
    /// The same endpoint as a plain request, to store a copy under the same key.
    var asOffline: OfflineGetRequest { OfflineGetRequest(url: url, cacheType: cacheType) }
}

/// GET request with an explicit cache type, used by the offline fallback tests.
struct OfflineGetRequest: HGetRequestProtocol {
    typealias Model = MockModel
    var url: String
    var cacheType: HCache.CacheType?
}

/// URLProtocol stub failing every request with `URLError.notConnectedToInternet`.
private final class NotConnectedStubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

/// Fake connectivity monitor for tests: reports a fixed connectivity state.
@HRequestManagerActor
final class FakeConnectivityMonitor: HRequestManagerMonitorProtocol {
    private let connected: Bool

    init(connected: Bool) {
        self.connected = connected
    }

    func start() {}

    func isConnectedToNetwork() -> Bool {
        connected
    }
}
