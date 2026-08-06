//
//  HarborRequestRetryTests.swift
//  Harbor
//
//  Tests for the retry loop, retry policy, auth retry guard and URLSession caching.
//

import XCTest
@testable import Harbor

/// URLProtocol stub injected through `HConfig.protocolClasses`, so networking is
/// intercepted per session without registering the protocol globally.
private final class HRequestStubProtocol: URLProtocol {
    enum Mode {
        case status(Int)
        case error(URLError)
        case statusSequence([Int])
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _startLoadingCount = 0
    nonisolated(unsafe) private static var _mode: Mode = .status(200)

    static var startLoadingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _startLoadingCount
    }

    static var mode: Mode {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _mode
        }
        set {
            lock.lock()
            _mode = newValue
            lock.unlock()
        }
    }

    static func reset() {
        lock.lock()
        _startLoadingCount = 0
        _mode = .status(200)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        Self.lock.lock()
        Self._startLoadingCount += 1
        let count = Self._startLoadingCount
        let currentMode = Self._mode
        Self.lock.unlock()

        let statusCode: Int
        switch currentMode {
        case .status(let code):
            statusCode = code
        case .statusSequence(let codes):
            let index = min(count - 1, codes.count - 1)
            statusCode = codes[max(0, index)]
        case .error:
            statusCode = 0
        }

        switch currentMode {
        case .error(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .status, .statusSequence:
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{\"quote\":\"ok\"}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// Auth provider that issues a different header on every call and records its usage.
@HRequestManagerActor
private final class SpyAuthProvider: HAuthProviderProtocol {
    private(set) var headerCallCount = 0
    private(set) var authFailedCount = 0

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        headerCallCount += 1
        return HAuthorizationHeader(key: "Authorization", value: "Bearer token_\(headerCallCount)")
    }

    func authFailed() async {
        authFailedCount += 1
    }
}

private struct StubbedGetRequest: HGetRequestProtocol {
    typealias Model = MockModel

    var url: String
    var retryPolicy: HRetryPolicy?
    var headerParameters: [String: String]?
    var needsAuth: Bool = false

    init(url: String, retryPolicy: HRetryPolicy? = nil, headerParameters: [String: String]? = nil, needsAuth: Bool = false) {
        self.url = url
        self.retryPolicy = retryPolicy
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
    }
}

/// Request that needs auth but relies on the default `headerParameters`, which does not persist values.
/// The authorization header is applied to the built URLRequest, so the flow works anyway.
private struct HeaderlessAuthGetRequest: HGetRequestProtocol {
    typealias Model = MockModel

    var url: String { "https://example.com/secure" }
    var needsAuth: Bool { true }
}

@HRequestManagerActor
final class HarborRequestRetryTests: XCTestCase {

    override func setUp() async throws {
        await Harbor.removeAllMocks()
        await Harbor.setAuthProvider(nil)
        HConfig.shared.customURLSession = nil
        Harbor.setProtocolClasses([HRequestStubProtocol.self])
        HRequestStubProtocol.reset()
    }

    override func tearDown() async throws {
        await Harbor.removeAllMocks()
        await Harbor.setAuthProvider(nil)
        HConfig.shared.customURLSession = nil
        Harbor.setProtocolClasses(nil)
        HRequestStubProtocol.reset()
    }

    // MARK: - Retry Loop

    func testRetriesExhaustAllAttemptsOnServerError() async throws {
        // Given a stub that always answers 500 and a request with 2 retries
        HRequestStubProtocol.mode = .status(500)
        let request = StubbedGetRequest(url: "https://example.com/flaky", retryPolicy: HRetryPolicy(maxRetries: 2, baseDelay: 0.01, multiplier: 1, jitter: 0...0))

        // When
        let response = await request.request()

        // Then the initial attempt plus the 2 retries hit the stub exactly 3 times
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 3)

        guard case .error(let error) = response, case .api(let statusCode, _) = error else {
            XCTFail("Expected .api error but got: \(response)")
            return
        }
        XCTAssertEqual(statusCode, 500)
    }

    func testTransientNetworkErrorIsRetried() async throws {
        // Given a stub that always times out and a request with 1 retry
        HRequestStubProtocol.mode = .error(URLError(.timedOut))
        let request = StubbedGetRequest(url: "https://example.com/slow", retryPolicy: HRetryPolicy(maxRetries: 1, baseDelay: 0.01, multiplier: 1, jitter: 0...0))

        // When
        let response = await request.request()

        // Then the timeout is retried once before surfacing
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 2)

        guard case .error(let error) = response, case .timeout = error else {
            XCTFail("Expected .timeout but got: \(response)")
            return
        }
    }

    func testConnectionLostIsRetriedAndMappedToNoConnection() async throws {
        // Given a stub that always drops the connection and a request with 1 retry
        HRequestStubProtocol.mode = .error(URLError(.networkConnectionLost))
        let request = StubbedGetRequest(url: "https://example.com/drop", retryPolicy: HRetryPolicy(maxRetries: 1, baseDelay: 0.01, multiplier: 1, jitter: 0...0))

        // When
        let response = await request.request()

        // Then the connection loss is retried once and mapped to .noConnection
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 2)

        guard case .error(let error) = response, case .noConnection = error else {
            XCTFail("Expected .noConnection but got: \(response)")
            return
        }
    }

    func testRetryTransitionsFromFailureToSuccess() async throws {
        // Given a stub that returns 500 twice then 200, and a request with 2 retries
        HRequestStubProtocol.mode = .statusSequence([500, 500, 200])
        let request = StubbedGetRequest(url: "https://example.com/flaky-then-ok", retryPolicy: HRetryPolicy(maxRetries: 2, baseDelay: 0.01, multiplier: 1, jitter: 0...0))

        // When
        let response = await request.request()

        // Then the request eventually succeeds on the third attempt
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 3)

        guard case .success(let model) = response else {
            XCTFail("Expected success after a fail→success transition but got: \(response)")
            return
        }
        XCTAssertEqual(model.quote, "ok")
    }

    func testNoRetryByDefault() async throws {
        // Given a stub that always answers 500 and a request without retries
        HRequestStubProtocol.mode = .status(500)
        let request = StubbedGetRequest(url: "https://example.com/one-shot")

        // When
        let response = await request.request()

        // Then
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 1)

        guard case .error(let error) = response, case .api(let statusCode, _) = error else {
            XCTFail("Expected .api error but got: \(response)")
            return
        }
        XCTAssertEqual(statusCode, 500)
    }

    // MARK: - Retry Policy

    func testRetryPolicyBackoffProgression() async {
        // Given a policy with no jitter
        let policy = HRetryPolicy(maxRetries: 3, baseDelay: 0.5, multiplier: 2, jitter: 0...0)

        // Then the delay doubles on every retry
        XCTAssertEqual(policy.delay(forRetry: 1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forRetry: 2), 1.0, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forRetry: 3), 2.0, accuracy: 0.0001)
    }

    func testRetryPolicyJitterStaysWithinRange() async {
        // Given
        let policy = HRetryPolicy(maxRetries: 1, baseDelay: 0.3, multiplier: 1, jitter: 0...0.1)

        // Then
        for _ in 0 ..< 100 {
            let delay = policy.delay(forRetry: 1)
            XCTAssertGreaterThanOrEqual(delay, 0.3)
            XCTAssertLessThanOrEqual(delay, 0.4)
        }
    }

    func testRetryPolicyDelayIsClamped() async {
        // Given a policy whose backoff would exceed the maximum
        let policy = HRetryPolicy(maxRetries: 2, baseDelay: 100, multiplier: 10, jitter: 0...0)

        // Then
        XCTAssertEqual(policy.delay(forRetry: 2), HRetryPolicy.maxDelay, accuracy: 0.0001)
    }

    func testRetryPolicyMaxAttemptsIsAtLeastOne() async {
        // Given
        let policy = HRetryPolicy(maxRetries: -1)

        // Then
        XCTAssertEqual(policy.maxRetries, 0)
    }

    // MARK: - Auth Retry Guard

    func testAuthRetryIsBoundedAndFetchesHeaderOncePerAttempt() async throws {
        // Given a provider that issues a different header on every call and a stub that always answers 401
        let provider = SpyAuthProvider()
        await Harbor.setAuthProvider(provider)
        HRequestStubProtocol.mode = .status(401)

        let request = StubbedGetRequest(url: "https://example.com/secure", needsAuth: true)

        // When
        let response = await request.request()

        // Then the flow ends with .authNeeded after exactly maxAuthRetries + 1 attempts,
        // and the provider was asked for a header once per attempt
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, HRequestManager.maxAuthRetries + 1)
        XCTAssertEqual(provider.headerCallCount, HRequestManager.maxAuthRetries + 1)
        XCTAssertEqual(provider.authFailedCount, 1)

        guard case .error(let error) = response, case .authNeeded = error else {
            XCTFail("Expected .authNeeded but got: \(response)")
            return
        }
    }

    func testAuthFlowWorksWhenRequestDoesNotPersistHeaders() async throws {
        // Given a valid provider and a request whose headerParameters are not persisted
        let provider = SpyAuthProvider()
        await Harbor.setAuthProvider(provider)
        HRequestStubProtocol.mode = .status(401)

        let request = HeaderlessAuthGetRequest()

        // When
        let response = await request.request()

        // Then the request goes through the full auth flow (the header is applied to the
        // URLRequest, not to the request type): 401, one refresh, then .authNeeded
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, HRequestManager.maxAuthRetries + 1)
        XCTAssertEqual(provider.headerCallCount, HRequestManager.maxAuthRetries + 1)
        XCTAssertEqual(provider.authFailedCount, 1)

        guard case .error(let error) = response, case .authNeeded = error else {
            XCTFail("Expected .authNeeded but got: \(response)")
            return
        }
    }

    // MARK: - URLSession Caching

    func testSessionIsReusedAndRecreatedAfterSessionAffectingConfigChange() async {
        // Given no custom session, the internally built session is reused across requests
        let request = StubbedGetRequest(url: "https://example.com")

        let first = HRequestManager.getURLSession(for: request)
        let second = HRequestManager.getURLSession(for: request)
        XCTAssertTrue(first === second, "The internally built session should be reused across requests")

        // When a session-affecting setting changes
        HConfig.shared.timeoutInterval = 30
        defer { HConfig.shared.timeoutInterval = 15 }

        // Then a new session is built
        let third = HRequestManager.getURLSession(for: request)
        XCTAssertFalse(third === first, "A session-affecting config change should rebuild the session")
    }

    func testCustomSessionIsNeverReplacedByTheCache() async {
        // Given a user-provided session
        let providedSession = URLSession(configuration: .default)
        await Harbor.setCustomURLSession(providedSession)

        // When a session-affecting setting changes
        HConfig.shared.timeoutInterval = 45
        defer { HConfig.shared.timeoutInterval = 15 }

        // Then the provided session is still used as-is
        let request = StubbedGetRequest(url: "https://example.com")
        let session = HRequestManager.getURLSession(for: request)
        XCTAssertTrue(session === providedSession, "A user-provided session should never be replaced by the cache")
    }
}
