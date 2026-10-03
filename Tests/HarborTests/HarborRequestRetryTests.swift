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
    /// One scripted answer: an HTTP status (with optional headers) or a transport failure.
    enum Outcome {
        case status(Int, headers: [String: String]? = nil)
        case failure(any Error)
    }

    enum Mode {
        case status(Int)
        case error(URLError)
        case statusSequence([Int])
        /// Scripted outcomes played in order; the last one repeats.
        case outcomes([Outcome])
        /// Answers 200 when the Authorization header equals the given value, 401 otherwise.
        case unauthorizedUnless(authorization: String)
        /// Answers 304 (no body) when the request is conditional, 200 otherwise.
        case notModifiedWhenConditional
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _startLoadingCount = 0
    nonisolated(unsafe) private static var _mode: Mode = .status(200)
    nonisolated(unsafe) private static var _receivedRequests: [URLRequest] = []

    static var startLoadingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _startLoadingCount
    }

    static var receivedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _receivedRequests
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
        _receivedRequests = []
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
        Self._receivedRequests.append(request)
        let count = Self._startLoadingCount
        let currentMode = Self._mode
        Self.lock.unlock()

        let outcome: Outcome
        switch currentMode {
        case .status(let code):
            outcome = .status(code)
        case .statusSequence(let codes):
            outcome = .status(codes[max(0, min(count - 1, codes.count - 1))])
        case .error(let error):
            outcome = .failure(error)
        case .outcomes(let outcomes):
            outcome = outcomes[max(0, min(count - 1, outcomes.count - 1))]
        case .unauthorizedUnless(let authorization):
            outcome = .status(request.value(forHTTPHeaderField: "Authorization") == authorization ? 200 : 401)
        case .notModifiedWhenConditional:
            outcome = .status(request.value(forHTTPHeaderField: "If-None-Match") != nil ? 304 : 200)
        }

        switch outcome {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .status(let statusCode, let headers):
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if statusCode != 304 {
                client?.urlProtocol(self, didLoad: Data("{\"quote\":\"ok\"}".utf8))
            }
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

/// Auth provider whose token is rotated only by `authFailed()`, which takes a while to
/// complete, so concurrent 401s overlap with the in-flight refresh.
@HRequestManagerActor
private final class SlowRefreshAuthProvider: HAuthProviderProtocol {
    private(set) var authFailedCount = 0
    private var token = "Bearer stale"

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        HAuthorizationHeader(key: "Authorization", value: token)
    }

    func authFailed() async {
        authFailedCount += 1
        try? await Task.sleep(nanoseconds: 300_000_000)
        token = "Bearer fresh"
    }
}

/// Auth provider whose header was already rotated by another request's refresh: the first
/// call returns the stale header `H`, every later call the rotated `H2`.
@HRequestManagerActor
private final class RotatedElsewhereAuthProvider: HAuthProviderProtocol {
    private(set) var authFailedCount = 0
    private var headerCallCount = 0

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        headerCallCount += 1
        return HAuthorizationHeader(key: "Authorization", value: headerCallCount == 1 ? "Bearer H" : "Bearer H2")
    }

    func authFailed() async {
        authFailedCount += 1
    }
}

/// POST request with a configurable retry policy, answered by the stub.
private struct StubbedPostRequest: HPostRequestProtocol, @unchecked Sendable {
    var url: String
    var retryPolicy: HRetryPolicy?
    var bodyParameters: [String: Any]? = ["key": "value"]
}

/// GET request with a per-request timeout, answered by the stub.
private struct TimeoutStubbedGetRequest: HGetRequestProtocol {
    typealias Model = MockModel
    var url: String
    var timeoutInterval: TimeInterval?
}

/// GET request with an explicit cache type, answered by the stub.
private struct CacheTypeStubbedGetRequest: HGetRequestProtocol {
    typealias Model = MockModel
    var url: String
    var cacheType: HCache.CacheType?
}

/// Non-URLError failure surfaced by the stub's transport.
private struct StubTransportError: Error, Equatable {}

private extension HResponse {
    /// The error carried by the response, or `nil` on success.
    var failure: HRequestError? {
        if case .error(let error) = self { return error }
        return nil
    }
}

private extension HResponseWithResult {
    /// The error carried by the response, or `nil` on success.
    var failure: HRequestError? {
        if case .error(let error) = self { return error }
        return nil
    }
}

/// Request that needs auth but relies on the default `headerParameters`, which does not persist values.
/// The authorization header is applied to the built URLRequest, so the flow works anyway.

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
        Harbor.setDefaultCacheType(.urlCache())
        await Harbor.clearAllCache()
        HRequestStubProtocol.reset()
    }

    /// Retry policy with near-instant, deterministic backoff.
    private func fastPolicy(maxRetries: Int, retryableStatusCodes: Set<Int> = HRetryPolicy.defaultRetryableStatusCodes, retryNonIdempotentRequests: Bool = false) -> HRetryPolicy {
        HRetryPolicy(maxRetries: maxRetries, baseDelay: 0.01, multiplier: 1, jitter: 0...0, retryableStatusCodes: retryableStatusCodes, retryNonIdempotentRequests: retryNonIdempotentRequests)
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

    func testSecureConnectionFailureIsRetriedAndMappedToNetworkFailure() async throws {
        // Given a stub whose TLS handshake always drops and an idempotent request with 1 retry
        HRequestStubProtocol.mode = .error(URLError(.secureConnectionFailed))
        let request = StubbedGetRequest(url: "https://example.com/tls-drop", retryPolicy: fastPolicy(maxRetries: 1))

        // When
        let response = await request.request()

        // Then the generic TLS failure is retried like a lost connection and is not reported
        // as a certificate error
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 2)
        XCTAssertEqual(response.failure, .networkFailure(URLError(.secureConnectionFailed)))
    }

    func testSecureConnectionFailureIsNotRetriedForNonIdempotentRequestsByDefault() async throws {
        // Given a stub whose TLS handshake always drops and a POST request with 1 retry
        HRequestStubProtocol.mode = .error(URLError(.secureConnectionFailed))
        let request = StubbedPostRequest(url: "https://example.com/tls-drop-post", retryPolicy: fastPolicy(maxRetries: 1))

        // When
        let response = await request.request()

        // Then the request may have reached the server, so it is not repeated without opting in
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 1)
        XCTAssertEqual(response.failure, .networkFailure(URLError(.secureConnectionFailed)))
    }

    func testRetryPolicyClassifiesTLSErrors() async {
        let policy = HRetryPolicy(maxRetries: 1)
        let optIn = HRetryPolicy(maxRetries: 1, retryNonIdempotentRequests: true)

        // A generic TLS failure is transient: retried for idempotent requests or by opt-in
        XCTAssertTrue(policy.shouldRetry(urlError: URLError(.secureConnectionFailed), method: .get))
        XCTAssertFalse(policy.shouldRetry(urlError: URLError(.secureConnectionFailed), method: .post))
        XCTAssertTrue(optIn.shouldRetry(urlError: URLError(.secureConnectionFailed), method: .post))

        // Certificate errors are never retried
        for code in [URLError.Code.serverCertificateUntrusted, .serverCertificateHasBadDate, .clientCertificateRejected] {
            XCTAssertFalse(optIn.shouldRetry(urlError: URLError(code), method: .get), "\(code) must not be retried")
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

    func testRetryPolicyClampsNegativeMaxRetriesToZero() async {
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

        // Then the flow ends with .authNeeded after exactly maxAuthRetries + 1 attempts and
        // the provider was asked for a header once per attempt. It already issues a header
        // different from the rejected one, so the retry needs no authFailed(); once the
        // retried attempt is rejected too, the provider is notified exactly once
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, HRequestManager.maxAuthRetries + 1)
        XCTAssertEqual(provider.headerCallCount, HRequestManager.maxAuthRetries + 1)
        XCTAssertEqual(provider.authFailedCount, 1)

        guard case .error(let error) = response, case .authNeeded = error else {
            XCTFail("Expected .authNeeded but got: \(response)")
            return
        }
    }

    func testAuthFailedIsCalledOnceWhenTheRefreshedAttemptIsRejectedToo() async throws {
        // Given a provider that only rotates its header in authFailed() and a server that always answers 401
        let provider = SlowRefreshAuthProvider()
        Harbor.setAuthProvider(provider)
        HRequestStubProtocol.mode = .status(401)

        // When
        let response = await StubbedGetRequest(url: "https://example.com/secure/always-401", needsAuth: true).request()

        // Then the refreshed header is tried once and the provider, already notified to obtain
        // it, is not notified again when giving up
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, HRequestManager.maxAuthRetries + 1)
        XCTAssertEqual(HRequestStubProtocol.receivedRequests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer stale", "Bearer fresh"])
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
        // URLRequest, not to the request type): 401, one re-attempt with the provider's
        // newer header (no authFailed() needed for it), then authFailed() once and .authNeeded
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, HRequestManager.maxAuthRetries + 1)
        XCTAssertEqual(provider.headerCallCount, HRequestManager.maxAuthRetries + 1)
        XCTAssertEqual(provider.authFailedCount, 1)

        guard case .error(let error) = response, case .authNeeded = error else {
            XCTFail("Expected .authNeeded but got: \(response)")
            return
        }
    }

    // MARK: - Retry Classification

    func testClientErrorsAreNotRetried() async throws {
        for statusCode in [400, 404, 422] {
            // Given a stub that always answers a client error and a request with retries
            HRequestStubProtocol.reset()
            HRequestStubProtocol.mode = .status(statusCode)
            let request = StubbedGetRequest(url: "https://example.com/client-error", retryPolicy: fastPolicy(maxRetries: 2))

            // When
            let response = await request.request()

            // Then the error is returned after a single attempt
            XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 1, "Status \(statusCode) must not be retried")
            guard case .error(let error) = response, case .api(let receivedStatus, _) = error else {
                XCTFail("Expected .api error but got: \(response)")
                continue
            }
            XCTAssertEqual(receivedStatus, statusCode)
        }
    }

    func testDefaultRetryableStatusCodesAreRetried() async throws {
        for statusCode in HRetryPolicy.defaultRetryableStatusCodes.sorted() {
            // Given a stub that fails once with a retryable status and then succeeds
            HRequestStubProtocol.reset()
            HRequestStubProtocol.mode = .statusSequence([statusCode, 200])
            let request = StubbedGetRequest(url: "https://example.com/transient", retryPolicy: fastPolicy(maxRetries: 1))

            // When
            let response = await request.request()

            // Then
            XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 2, "Status \(statusCode) should be retried")
            guard case .success = response else {
                XCTFail("Expected success after retrying \(statusCode) but got: \(response)")
                continue
            }
        }
    }

    func testCustomRetryableStatusCodesAreHonored() async throws {
        // Given a policy that treats 404 as retryable and excludes 500
        HRequestStubProtocol.mode = .statusSequence([404, 500])
        let request = StubbedGetRequest(url: "https://example.com/custom", retryPolicy: fastPolicy(maxRetries: 3, retryableStatusCodes: [404]))

        // When
        let response = await request.request()

        // Then the 404 is retried and the 500 is returned as-is
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 2)
        guard case .error(let error) = response, case .api(let statusCode, _) = error else {
            XCTFail("Expected .api error but got: \(response)")
            return
        }
        XCTAssertEqual(statusCode, 500)
    }

    func testNonIdempotentRequestIsNotRetriedOnServerErrorByDefault() async throws {
        // Given a POST with retries and a stub that always answers 503
        HRequestStubProtocol.mode = .status(503)
        let request = StubbedPostRequest(url: "https://example.com/create", retryPolicy: fastPolicy(maxRetries: 2))

        // When
        let response = await request.request()

        // Then the POST is not repeated
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 1)
        XCTAssertEqual(response.failure, .api(statusCode: 503, data: Data("{\"quote\":\"ok\"}".utf8)))
    }

    func testNonIdempotentRequestIsRetriedWhenOptedIn() async throws {
        // Given a POST whose policy opts in to non-idempotent retries
        HRequestStubProtocol.mode = .statusSequence([503, 200])
        let request = StubbedPostRequest(url: "https://example.com/create", retryPolicy: fastPolicy(maxRetries: 2, retryNonIdempotentRequests: true))

        // When
        let response = await request.request()

        // Then
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 2)
        XCTAssertNil(response.failure)
    }

    func testNonIdempotentRequestIsNotRetriedOnTimeoutByDefault() async throws {
        // Given a POST that times out: the server may already have processed it
        HRequestStubProtocol.mode = .error(URLError(.timedOut))
        let request = StubbedPostRequest(url: "https://example.com/create", retryPolicy: fastPolicy(maxRetries: 2))

        // When
        let response = await request.request()

        // Then
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 1)
        XCTAssertEqual(response.failure, .timeout)
    }

    func testNonIdempotentRequestIsRetriedWhenConnectionWasNeverEstablished() async throws {
        // Given a POST that could not connect: the request never reached the server
        HRequestStubProtocol.mode = .outcomes([.failure(URLError(.cannotConnectToHost)), .status(200)])
        let request = StubbedPostRequest(url: "https://example.com/create", retryPolicy: fastPolicy(maxRetries: 2))

        // When
        let response = await request.request()

        // Then
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 2)
        XCTAssertNil(response.failure)
    }

    func testNonTransientURLErrorsAreNotRetried() async throws {
        let expectations: [(URLError.Code, HRequestError)] = [
            (.serverCertificateUntrusted, .certificate),
            (.badURL, .malformedRequest(reason: "Invalid URL: \(URLError(.badURL).localizedDescription)")),
            (.badServerResponse, .networkFailure(URLError(.badServerResponse)))
        ]

        for (code, expectedError) in expectations {
            // Given a request with retries and a stub failing with a non-transient error
            HRequestStubProtocol.reset()
            HRequestStubProtocol.mode = .error(URLError(code))
            let request = StubbedGetRequest(url: "https://example.com/fatal", retryPolicy: fastPolicy(maxRetries: 2))

            // When
            let response = await request.request()

            // Then
            XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 1, "\(code) must not be retried")
            guard case .error(let error) = response else {
                XCTFail("Expected an error for \(code) but got: \(response)")
                continue
            }
            XCTAssertEqual(error, expectedError)
        }
    }

    func testNonURLErrorIsPreservedAndNotRetried() async throws {
        // Given a transport failing with an error that is not a URLError
        HRequestStubProtocol.mode = .outcomes([.failure(StubTransportError())])
        let request = StubbedGetRequest(url: "https://example.com/odd", retryPolicy: fastPolicy(maxRetries: 2))

        // When
        let response = await request.request()

        // Then the request is not retried and the underlying error is preserved
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 1)
        guard case .error(let error) = response, case .unknown(let underlying) = error else {
            XCTFail("Expected .unknown but got: \(response)")
            return
        }
        XCTAssertEqual((underlying as NSError).domain, (StubTransportError() as NSError).domain)
    }

    // MARK: - Retry-After

    func testRetryAfterDeltaSecondsIsHonored() async throws {
        // Given a 429 asking to wait one second, and a policy with a negligible backoff
        HRequestStubProtocol.mode = .outcomes([.status(429, headers: ["Retry-After": "1"]), .status(200)])
        let request = StubbedGetRequest(url: "https://example.com/limited", retryPolicy: fastPolicy(maxRetries: 1))

        // When
        let start = Date()
        let response = await request.request()
        let elapsed = Date().timeIntervalSince(start)

        // Then the retry waited for the server-provided delay
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 2)
        XCTAssertGreaterThanOrEqual(elapsed, 0.9)
        guard case .success = response else {
            XCTFail("Expected success but got: \(response)")
            return
        }
    }

    func testRetryAfterParsing() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        func response(_ value: String?) -> HTTPURLResponse? {
            HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: value.map { ["Retry-After": $0] })
        }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        // Delta-seconds
        XCTAssertEqual(HRequestManager.retryAfterDelay(statusCode: 503, httpResponse: response("5"), now: now), 5)
        XCTAssertEqual(HRequestManager.retryAfterDelay(statusCode: 429, httpResponse: response(" 0 "), now: now), 0)
        // HTTP-date
        let date = formatter.string(from: now.addingTimeInterval(10))
        XCTAssertEqual(try XCTUnwrap(HRequestManager.retryAfterDelay(statusCode: 503, httpResponse: response(date), now: now)), 10, accuracy: 1)
        // A date in the past means "retry now"
        let past = formatter.string(from: now.addingTimeInterval(-10))
        XCTAssertEqual(HRequestManager.retryAfterDelay(statusCode: 503, httpResponse: response(past), now: now), 0)
        // Not capped: the server's value is reported as-is
        XCTAssertEqual(HRequestManager.retryAfterDelay(statusCode: 429, httpResponse: response("3600"), now: now), 3600)
        // Invalid, missing, or on a status that does not define it
        XCTAssertNil(HRequestManager.retryAfterDelay(statusCode: 503, httpResponse: response("soon"), now: now))
        XCTAssertNil(HRequestManager.retryAfterDelay(statusCode: 503, httpResponse: response("-1"), now: now))
        XCTAssertNil(HRequestManager.retryAfterDelay(statusCode: 503, httpResponse: response(nil), now: now))
        XCTAssertNil(HRequestManager.retryAfterDelay(statusCode: 500, httpResponse: response("5"), now: now))

        // A Retry-After up to the maximum delay is honored; a longer one stops the retries
        XCTAssertEqual(HRequestManager.statusRetry(statusCode: 429, httpResponse: response("5"), now: now), .retry(after: 5))
        XCTAssertEqual(HRequestManager.statusRetry(statusCode: 503, httpResponse: response("\(Int(HRetryPolicy.maxDelay))"), now: now), .retry(after: HRetryPolicy.maxDelay))
        XCTAssertEqual(HRequestManager.statusRetry(statusCode: 429, httpResponse: response("3600"), now: now), .giveUp)
        XCTAssertEqual(HRequestManager.statusRetry(statusCode: 503, httpResponse: response(nil), now: now), .retry(after: nil))
        XCTAssertEqual(HRequestManager.statusRetry(statusCode: 500, httpResponse: response("3600"), now: now), .retry(after: nil))
    }

    func testRetryAfterLongerThanMaxDelayStopsRetrying() async throws {
        // Given a 429 asking to wait longer than HRetryPolicy.maxDelay, and a policy with retries
        HRequestStubProtocol.mode = .outcomes([.status(429, headers: ["Retry-After": "3600"]), .status(200)])
        let request = StubbedGetRequest(url: "https://example.com/limited-long", retryPolicy: fastPolicy(maxRetries: 2))

        // When
        let start = Date()
        let response = await request.request()

        // Then the request is not retried: the 429 is returned right away so the caller sees
        // the server's hint, instead of retrying after a clamped delay
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        guard case .error(let error) = response, case .api(let statusCode, _) = error else {
            XCTFail("Expected .api(429) but got: \(response)")
            return
        }
        XCTAssertEqual(statusCode, 429)
    }

    func testRetryAfterLongerThanMaxDelayStopsRetryingEmptyResponseRequests() async throws {
        // Given a 503 asking to wait longer than HRetryPolicy.maxDelay on a request without a result
        HRequestStubProtocol.mode = .outcomes([.status(503, headers: ["Retry-After": "3600"]), .status(200)])
        let request = StubbedPostRequest(url: "https://example.com/limited-long-post", retryPolicy: fastPolicy(maxRetries: 2, retryNonIdempotentRequests: true))

        // When
        let response = await request.request()

        // Then
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 1)
        XCTAssertEqual(response.failure, .api(statusCode: 503, data: Data("{\"quote\":\"ok\"}".utf8)))
    }

    // MARK: - Cancellation

    func testCancellationDuringBackoffStopsRetrying() async throws {
        // Given a request whose retry backoff is long
        HRequestStubProtocol.mode = .status(500)
        let request = StubbedGetRequest(url: "https://example.com/slow-backoff", retryPolicy: HRetryPolicy(maxRetries: 3, baseDelay: 5, multiplier: 1, jitter: 0...0))

        // When the task is cancelled while waiting for the first retry
        let start = Date()
        let task = Task { await request.request() }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let response = await task.value

        // Then no further attempt is made and the request finishes as cancelled
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 1)
        XCTAssertEqual(response.failure, .cancelled)
    }

    // MARK: - Stale Fallback Ordering

    func testTransientNetworkErrorIsRetriedBeforeServingStaleCache() async throws {
        // Given a stale servable entry and a transport that fails once, then recovers
        Harbor.setDefaultCacheType(.custom(HCache.Configuration(expirationTime: .oneHour)))
        await Harbor.clearAllCache()
        let request = StubbedGetRequest(url: "https://example.com/stale-retry", retryPolicy: fastPolicy(maxRetries: 1))
        let url = try XCTUnwrap(URL(string: request.url))
        let cachedResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "max-age=0, stale-if-error=300"])
        await request.saveCache(Data("{\"quote\":\"stale\"}".utf8), response: cachedResponse, authHeader: nil)
        HRequestStubProtocol.mode = .outcomes([.failure(URLError(.timedOut)), .status(200)])

        // When
        let response = await request.request()

        // Then the retry runs first and its fresh body wins over the stale one
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 2)
        guard case .success(let model) = response else {
            XCTFail("Expected success but got: \(response)")
            return
        }
        XCTAssertEqual(model.quote, "ok")
    }

    func testStaleCacheIsServedOnceRetriesAreExhausted() async throws {
        // Given a stale servable entry and a transport that keeps timing out
        Harbor.setDefaultCacheType(.custom(HCache.Configuration(expirationTime: .oneHour)))
        await Harbor.clearAllCache()
        let request = StubbedGetRequest(url: "https://example.com/stale-exhausted", retryPolicy: fastPolicy(maxRetries: 1))
        let url = try XCTUnwrap(URL(string: request.url))
        let cachedResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "max-age=0, stale-if-error=300"])
        await request.saveCache(Data("{\"quote\":\"stale\"}".utf8), response: cachedResponse, authHeader: nil)
        HRequestStubProtocol.mode = .error(URLError(.timedOut))

        // When
        let response = await request.request()

        // Then
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 2)
        guard case .success(let model) = response else {
            XCTFail("Expected the stale body but got: \(response)")
            return
        }
        XCTAssertEqual(model.quote, "stale")
    }

    // MARK: - 304 Without Cached Body

    func testNotModifiedWithoutCachedBodyRefetchesUnconditionallyWhenHarborInjectedTheValidators() async throws {
        // Given a custom-cache entry whose validator Harbor injects, but whose body this
        // request cannot decode, so a 304 cannot be served from the cache
        Harbor.setDefaultCacheType(.custom(HCache.Configuration(expirationTime: .oneHour)))
        await Harbor.clearAllCache()
        HRequestStubProtocol.mode = .notModifiedWhenConditional
        let request = StubbedGetRequest(url: "https://example.com/not-modified")
        let url = try XCTUnwrap(URL(string: request.url))
        let storeResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "max-age=0", "ETag": "\"etag\""])
        await request.saveCache(Data("{\"other\":true}".utf8), response: storeResponse, authHeader: nil)

        // When
        let response = await request.request()

        // Then the request is re-issued once without validators and its body is returned
        let received = HRequestStubProtocol.receivedRequests
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.first?.value(forHTTPHeaderField: "If-None-Match"), "\"etag\"")
        XCTAssertNil(received.last?.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertNil(received.last?.value(forHTTPHeaderField: "If-Modified-Since"))
        guard case .success(let model) = response else {
            XCTFail("Expected success but got: \(response)")
            return
        }
        XCTAssertEqual(model.quote, "ok")
    }

    func testNotModifiedForCallerProvidedValidatorsIsReturnedToTheCaller() async throws {
        // Given a request carrying its own conditional header and nothing cached by Harbor
        HRequestStubProtocol.mode = .notModifiedWhenConditional
        let request = StubbedGetRequest(url: "https://example.com/caller-validators", headerParameters: ["If-None-Match": "\"etag\""])

        // When
        let response = await request.request()

        // Then the caller owns the revalidation: its validators are not stripped and the
        // 304 is returned as is
        let received = HRequestStubProtocol.receivedRequests
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.value(forHTTPHeaderField: "If-None-Match"), "\"etag\"")
        XCTAssertEqual(response.failure, .api(statusCode: 304, data: Data()))
    }

    func testUnconditional304IsNotRefetched() async throws {
        // Given a server answering 304 to a request without validators
        HRequestStubProtocol.mode = .status(304)
        let request = StubbedGetRequest(url: "https://example.com/odd-304")

        // When
        let response = await request.request()

        // Then
        XCTAssertEqual(HRequestStubProtocol.startLoadingCount, 1)
        XCTAssertEqual(response.failure, .api(statusCode: 304, data: Data()))
    }

    // MARK: - Auth Failure Coalescing

    func testConcurrent401sShareASingleAuthFailedCall() async throws {
        // Given a provider whose refresh is slow and a server accepting only the refreshed token
        let provider = SlowRefreshAuthProvider()
        Harbor.setAuthProvider(provider)
        HRequestStubProtocol.mode = .unauthorizedUnless(authorization: "Bearer fresh")

        // When 5 requests are rejected concurrently with the same stale token
        let responses = await withTaskGroup(of: Bool.self) { group in
            for index in 0 ..< 5 {
                group.addTask {
                    let request = StubbedGetRequest(url: "https://example.com/secure/\(index)", needsAuth: true)
                    if case .success = await request.request() {
                        return true
                    }
                    return false
                }
            }
            var results: [Bool] = []
            for await succeeded in group {
                results.append(succeeded)
            }
            return results
        }

        // Then authFailed() runs once and every request succeeds with the refreshed token
        XCTAssertEqual(provider.authFailedCount, 1)
        XCTAssertEqual(responses, Array(repeating: true, count: 5))
    }

    func testLate401ForAnAlreadyRotatedHeaderRetriesWithoutAnotherRefresh() async throws {
        // Given a provider whose header was rotated (H -> H2) by another request's refresh
        // after this request was sent with H, and a server accepting only H2
        let provider = RotatedElsewhereAuthProvider()
        Harbor.setAuthProvider(provider)
        HRequestStubProtocol.mode = .unauthorizedUnless(authorization: "Bearer H2")

        // When the 401 for H arrives
        let response = await StubbedGetRequest(url: "https://example.com/secure/late", needsAuth: true).request()

        // Then the request is retried with the current header and authFailed() is not called again
        guard case .success = response else {
            XCTFail("Expected success with the rotated header but got: \(response)")
            return
        }
        XCTAssertEqual(provider.authFailedCount, 0)
        XCTAssertEqual(HRequestStubProtocol.receivedRequests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer H", "Bearer H2"])
    }

    func test401ForTheCurrentHeaderStillNotifiesTheProvider() async throws {
        // Given a provider that only rotates its header in authFailed()
        let provider = SlowRefreshAuthProvider()
        Harbor.setAuthProvider(provider)
        HRequestStubProtocol.mode = .unauthorizedUnless(authorization: "Bearer fresh")

        // When the current header is rejected
        let response = await StubbedGetRequest(url: "https://example.com/secure/current", needsAuth: true).request()

        // Then the provider is asked to refresh once and the retry succeeds
        guard case .success = response else {
            XCTFail("Expected success after the refresh but got: \(response)")
            return
        }
        XCTAssertEqual(provider.authFailedCount, 1)
    }

    // MARK: - URLSession Caching

    func testLeasedSessionStaysUsableAfterInvalidationUntilReleased() async throws {
        // Given a session leased by an in-flight attempt
        let request = StubbedGetRequest(url: "https://example.com/leased")
        let session = HRequestManager.leaseURLSession(for: request)

        // When a session-affecting setting changes while the attempt still holds it
        Harbor.setDefaultTimeoutInterval(30)
        defer { Harbor.setDefaultTimeoutInterval(15) }

        // Then the session is retired, not invalidated: a task can still be created on it
        // (creating a task on an invalidated session raises an Objective-C exception)
        XCTAssertFalse(HRequestManager.getURLSession(for: request) === session)
        XCTAssertEqual(HRequestManager.retiredURLSessionCount, 1)
        let task = session.dataTask(with: try XCTUnwrap(URL(string: "https://example.com/leased")))
        task.cancel()

        // And it is invalidated once the attempt releases it
        HRequestManager.releaseURLSession(session)
        XCTAssertEqual(HRequestManager.retiredURLSessionCount, 0)
    }

    func testRequestsSurviveSessionInvalidationsWhileInFlight() async throws {
        // Given many concurrent requests and repeated invalidations
        // When sessions are invalidated while the requests run
        let successes = await withTaskGroup(of: Bool.self) { group in
            for index in 0 ..< 30 {
                group.addTask {
                    let response = await StubbedGetRequest(url: "https://example.com/churn/\(index % 3)").request()
                    if case .success = response { return true }
                    return false
                }
                group.addTask {
                    await HRequestManager.invalidateURLSession()
                    return true
                }
            }
            var results: [Bool] = []
            for await result in group { results.append(result) }
            return results
        }

        // Then no attempt crashes on an invalidated session and every request completes
        XCTAssertEqual(successes.filter { $0 }.count, 60)
        XCTAssertEqual(HRequestManager.retiredURLSessionCount, 0)
    }

    func testSessionCacheEvictsOnlyTheLeastRecentlyUsedSession() async {
        // Given the session cache filled with sessions for distinct configurations
        func request(_ policy: NSURLRequest.CachePolicy) -> CacheTypeStubbedGetRequest {
            CacheTypeStubbedGetRequest(url: "https://example.com/lru", cacheType: .urlCache(urlCache: .shared, requestCachePolicy: policy))
        }
        let first = HRequestManager.getURLSession(for: request(.useProtocolCachePolicy))
        let second = HRequestManager.getURLSession(for: request(.reloadIgnoringLocalCacheData))
        let third = HRequestManager.getURLSession(for: request(.returnCacheDataElseLoad))
        let fourth = HRequestManager.getURLSession(for: request(.returnCacheDataDontLoad))

        // When the oldest one is used again and a fifth configuration needs a session
        XCTAssertTrue(HRequestManager.getURLSession(for: request(.useProtocolCachePolicy)) === first)
        _ = HRequestManager.getURLSession(for: request(.reloadRevalidatingCacheData))

        // Then only the least recently used session is dropped
        XCTAssertTrue(HRequestManager.getURLSession(for: request(.useProtocolCachePolicy)) === first)
        XCTAssertTrue(HRequestManager.getURLSession(for: request(.returnCacheDataElseLoad)) === third)
        XCTAssertTrue(HRequestManager.getURLSession(for: request(.returnCacheDataDontLoad)) === fourth)
        XCTAssertFalse(HRequestManager.getURLSession(for: request(.reloadIgnoringLocalCacheData)) === second)
    }

    func testSessionIsReusedAndRecreatedAfterSessionAffectingConfigChange() async {
        // Given no custom session, the internally built session is reused across requests
        let request = StubbedGetRequest(url: "https://example.com")

        let first = HRequestManager.getURLSession(for: request)
        let second = HRequestManager.getURLSession(for: request)
        XCTAssertTrue(first === second, "The internally built session should be reused across requests")

        // When a session-affecting setting changes
        Harbor.setDefaultTimeoutInterval(30)
        defer { Harbor.setDefaultTimeoutInterval(15) }

        // Then a new session is built
        let third = HRequestManager.getURLSession(for: request)
        XCTAssertFalse(third === first, "A session-affecting config change should rebuild the session")
    }

    func testSessionIsReusedAcrossRequestsWithDifferentTimeouts() async throws {
        // Given requests alternating between per-request timeouts
        let short = TimeoutStubbedGetRequest(url: "https://example.com/short", timeoutInterval: 5)
        let long = TimeoutStubbedGetRequest(url: "https://example.com/long", timeoutInterval: 120)

        // Then they share one session: the timeout travels on each URLRequest instead
        let first = HRequestManager.getURLSession(for: short)
        XCTAssertTrue(HRequestManager.getURLSession(for: long) === first)
        XCTAssertTrue(HRequestManager.getURLSession(for: short) === first)

        // And the stub receives each request with its own timeout
        _ = await long.request()
        XCTAssertEqual(try XCTUnwrap(HRequestStubProtocol.receivedRequests.last).timeoutInterval, 120, accuracy: 0.001)
    }

    func testSessionsAreReusedWhenCacheTypeAlternates() async {
        // Given requests alternating between the custom cache and URLCache
        let custom = CacheTypeStubbedGetRequest(url: "https://example.com/custom", cacheType: .custom(HCache.Configuration()))
        let urlCache = CacheTypeStubbedGetRequest(url: "https://example.com/url-cache", cacheType: .urlCache())

        // When
        let customSession = HRequestManager.getURLSession(for: custom)
        let urlCacheSession = HRequestManager.getURLSession(for: urlCache)

        // Then each keeps its own session instead of rebuilding on every switch
        XCTAssertFalse(customSession === urlCacheSession)
        XCTAssertTrue(HRequestManager.getURLSession(for: custom) === customSession)
        XCTAssertTrue(HRequestManager.getURLSession(for: urlCache) === urlCacheSession)
    }

    func testInternallyBuiltSessionKeepsTheSystemResourceTimeout() async {
        // Given no resource timeout configured
        let request = StubbedGetRequest(url: "https://example.com")

        // Then long transfers are not bounded by the per-request timeout
        let session = HRequestManager.getURLSession(for: request)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, URLSessionConfiguration.default.timeoutIntervalForResource)

        // When a resource timeout is configured, it applies to a rebuilt session
        Harbor.setDefaultResourceTimeoutInterval(600)
        defer { Harbor.setDefaultResourceTimeoutInterval(nil) }
        XCTAssertEqual(HRequestManager.getURLSession(for: request).configuration.timeoutIntervalForResource, 600, accuracy: 0.001)
    }

    func testInternallyBuiltSessionAlwaysUsesHarborDelegate() async {
        // Given no pinning nor mTLS, the session still gets Harbor's delegate (redirect policy)
        let session = HRequestManager.getURLSession(for: StubbedGetRequest(url: "https://example.com"))
        XCTAssertTrue(session.delegate is HURLSessionDelegate)
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
