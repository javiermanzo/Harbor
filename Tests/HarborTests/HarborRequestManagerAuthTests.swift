//
//  HarborRequestManagerAuthTests.swift
//  Harbor
//
//  Created by Jalil on 05/11/24.
//

import XCTest
@testable import Harbor

private final class MockAuthProvider: HAuthProviderProtocol {
    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        return HAuthorizationHeader(key: "Authorization", value: "Bearer mock_token")
    }

    func authFailed() async {
        // Handle auth failure logic if needed.
    }
}

/// Auth provider that returns a scripted sequence of headers and records its usage.
/// A `nil` element means the provider has no credentials at that point.
@HRequestManagerActor
private final class SpyAuthProvider: HAuthProviderProtocol {
    private(set) var headerCallCount = 0
    private(set) var authFailedCount = 0
    private var headers: [HAuthorizationHeader?]

    init(headers: [HAuthorizationHeader?]) {
        self.headers = headers
    }

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        headerCallCount += 1
        guard !headers.isEmpty else { return nil }
        return headers.removeFirst()
    }

    func authFailed() async {
        authFailedCount += 1
    }
}

/// URLProtocol stub injected through `HConfig.protocolClasses`. It answers with a scripted
/// sequence of status codes (repeating the last one) and records the Authorization header
/// of every request it sees. Optionally it sends response headers (e.g. `Vary`, `ETag`),
/// answers `304 Not Modified` when the request's `If-None-Match` matches the configured
/// ETag, and echoes the Authorization header in the body.
private final class AuthStubProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _statusCodes: [Int] = [200]
    nonisolated(unsafe) private static var _receivedAuthorizations: [String?] = []
    nonisolated(unsafe) private static var _receivedIfNoneMatch: [String?] = []
    nonisolated(unsafe) private static var _responseHeaders: [String: String]?
    nonisolated(unsafe) private static var _etag: String?
    nonisolated(unsafe) private static var _bodyIncludesAuthorization = false

    static var receivedAuthorizations: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return _receivedAuthorizations
    }

    static var receivedIfNoneMatch: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return _receivedIfNoneMatch
    }

    static var statusCodes: [Int] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _statusCodes
        }
        set {
            lock.lock()
            _statusCodes = newValue
            lock.unlock()
        }
    }

    static var responseHeaders: [String: String]? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _responseHeaders
        }
        set {
            lock.lock()
            _responseHeaders = newValue
            lock.unlock()
        }
    }

    static var etag: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _etag
        }
        set {
            lock.lock()
            _etag = newValue
            lock.unlock()
        }
    }

    static var bodyIncludesAuthorization: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _bodyIncludesAuthorization
        }
        set {
            lock.lock()
            _bodyIncludesAuthorization = newValue
            lock.unlock()
        }
    }

    static func reset() {
        lock.lock()
        _statusCodes = [200]
        _receivedAuthorizations = []
        _receivedIfNoneMatch = []
        _responseHeaders = nil
        _etag = nil
        _bodyIncludesAuthorization = false
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        // Only stub the hosts the tests target; anything else fails loudly.
        return request.url?.host == "example.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        Self.lock.lock()
        let index = Self._receivedAuthorizations.count
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let ifNoneMatch = request.value(forHTTPHeaderField: "If-None-Match")
        Self._receivedAuthorizations.append(authorization)
        Self._receivedIfNoneMatch.append(ifNoneMatch)
        let statusCodes = Self._statusCodes
        let responseHeaders = Self._responseHeaders
        let etag = Self._etag
        let bodyIncludesAuthorization = Self._bodyIncludesAuthorization
        Self.lock.unlock()

        var statusCode = statusCodes[min(index, statusCodes.count - 1)]
        if let etag, ifNoneMatch == etag {
            statusCode = 304
        }

        var headerFields = responseHeaders ?? [:]
        if let etag {
            headerFields["ETag"] = etag
        }

        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headerFields) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if statusCode != 304 {
            let quote = bodyIncludesAuthorization ? (authorization ?? "none") : "ok"
            client?.urlProtocol(self, didLoad: Data("{\"quote\":\"\(quote)\"}".utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Reference-type request conformer: the auth flow must never mutate the caller's instance.
private final class ClassAuthGetRequest: HGetRequestProtocol, @unchecked Sendable {
    typealias Model = MockModel

    let url: String
    var headerParameters: [String: String]?
    let needsAuth: Bool

    init(url: String, headerParameters: [String: String]? = nil, needsAuth: Bool = true) {
        self.url = url
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
    }
}

extension HRequestError: Equatable {
    public static func ==(lhs: HRequestError, rhs: HRequestError) -> Bool {
        switch (lhs, rhs) {
        case (.authProviderNeeded, .authProviderNeeded):
            return true
        case (.noConnection, .noConnection):
            return true
        case (.malformedRequest, .malformedRequest):
            return true
        case (.timeout, .timeout):
            return true
        case (.invalidHttpResponse, .invalidHttpResponse):
            return true
        case (.codable(let lhsModel, _), .codable(let rhsModel, _)):
            return lhsModel == rhsModel
        case (.api(let lhsStatusCode, _), .api(let rhsStatusCode, _)):
            return lhsStatusCode == rhsStatusCode
        default:
            return false
        }
    }
}

@HRequestManagerActor
final class HarborRequestManagerAuthTests: XCTestCase {

    override func setUp() async throws {
        Harbor.removeAllMocks()
        Harbor.setAuthProvider(nil)
        HConfig.shared.customURLSession = nil
        Harbor.setProtocolClasses([AuthStubProtocol.self])
        AuthStubProtocol.reset()
    }

    override func tearDown() async throws {
        Harbor.removeAllMocks()
        Harbor.setAuthProvider(nil)
        HConfig.shared.customURLSession = nil
        Harbor.setProtocolClasses(nil)
        Harbor.setDefaultCacheType(.urlCache())
        await Harbor.clearAllCache()
        AuthStubProtocol.reset()
    }

    // MARK: - Authorization Header Resolution

    func testAuthorizationHeaderIfNeededWithAuthSuccess() async throws {
        // Given
        let mockAuthProvider = MockAuthProvider()
        HConfig.shared.authProvider = mockAuthProvider

        let mockRequest = MockGetRequest<String>(needsAuth: true, url: "https://example.com/mock_endpoint")

        // When
        let result = await HRequestManager.authorizationHeaderIfNeeded(for: mockRequest)

        // Then
        guard case .success(let authHeader) = result else {
            XCTFail("Expected the provider's authorization header")
            return
        }
        XCTAssertEqual(authHeader, HAuthorizationHeader(key: "Authorization", value: "Bearer mock_token"))
    }

    func testAuthorizationHeaderIfNeededWithoutAuth() async throws {
        // Given
        let mockAuthProvider = MockAuthProvider()
        HConfig.shared.authProvider = mockAuthProvider

        let mockRequest = MockGetRequest<String>(needsAuth: false, url: "https://example.com/mock_endpoint")

        // When
        let result = await HRequestManager.authorizationHeaderIfNeeded(for: mockRequest)

        // Then
        guard case .success(let authHeader) = result else {
            XCTFail("Expected success since auth is not needed")
            return
        }
        XCTAssertNil(authHeader, "Expected no authorization header since auth is not needed")
    }

    func testAuthorizationHeaderIfNeededWithoutProviderFails() async throws {
        // Given
        HConfig.shared.authProvider = nil

        let mockRequest = MockGetRequest<String>(needsAuth: true, url: "https://example.com/mock_endpoint")

        // When
        let result = await HRequestManager.authorizationHeaderIfNeeded(for: mockRequest)

        // Then
        guard case .failure(let error) = result, case .authProviderNeeded = error else {
            XCTFail("Expected .authProviderNeeded but got: \(result)")
            return
        }
    }

    // MARK: - Auth Flow With Stubbed Network

    func testAuthHeaderIsSentOnTheWireWithoutMutatingTheRequest() async throws {
        // Given a class-conformed request and a provider with credentials
        let provider = SpyAuthProvider(headers: [HAuthorizationHeader(key: "Authorization", value: "Bearer token_1")])
        Harbor.setAuthProvider(provider)
        AuthStubProtocol.statusCodes = [200]

        let request = ClassAuthGetRequest(url: "https://example.com/secure", headerParameters: ["X-Custom": "value"])

        // When
        let response = await request.request()

        // Then the request succeeds, the wire carried the provider's header, and the
        // caller's request object was not mutated
        guard case .success = response else {
            XCTFail("Expected success but got: \(response)")
            return
        }
        XCTAssertEqual(AuthStubProtocol.receivedAuthorizations, ["Bearer token_1"])
        XCTAssertEqual(request.headerParameters, ["X-Custom": "value"])
    }

    func testAuthRetryWithFreshHeaderDoesNotMutateTheRequest() async throws {
        // Given a class-conformed request, a provider that refreshes its token, and a 401 then a 200
        let provider = SpyAuthProvider(headers: [
            HAuthorizationHeader(key: "Authorization", value: "Bearer token_1"),
            HAuthorizationHeader(key: "Authorization", value: "Bearer token_2")
        ])
        Harbor.setAuthProvider(provider)
        AuthStubProtocol.statusCodes = [401, 200]

        let request = ClassAuthGetRequest(url: "https://example.com/secure")

        // When
        let response = await request.request()

        // Then the retry succeeds with the refreshed header, the provider was asked twice,
        // and the caller's request object kept its original (nil) headers
        guard case .success = response else {
            XCTFail("Expected success but got: \(response)")
            return
        }
        XCTAssertEqual(provider.headerCallCount, 2)
        XCTAssertEqual(AuthStubProtocol.receivedAuthorizations, ["Bearer token_1", "Bearer token_2"])
        XCTAssertNil(request.headerParameters)
    }

    func test401WithoutNewHeaderFromProviderGivesUpWithAuthNeeded() async throws {
        // Given a provider that has credentials once and none after the 401
        let provider = SpyAuthProvider(headers: [
            HAuthorizationHeader(key: "Authorization", value: "Bearer token_1"),
            nil
        ])
        Harbor.setAuthProvider(provider)
        AuthStubProtocol.statusCodes = [401]

        let request = ClassAuthGetRequest(url: "https://example.com/secure")

        // When
        let response = await request.request()

        // Then the flow ends with .authNeeded and authFailed was called exactly once
        guard case .error(let error) = response, case .authNeeded = error else {
            XCTFail("Expected .authNeeded but got: \(response)")
            return
        }
        XCTAssertEqual(provider.headerCallCount, 2)
        XCTAssertEqual(provider.authFailedCount, 1)
    }

    func testRequestWithoutCredentialsGoesOutWithoutAuthHeader() async throws {
        // Given a provider without credentials
        let provider = SpyAuthProvider(headers: [nil])
        Harbor.setAuthProvider(provider)
        AuthStubProtocol.statusCodes = [200]

        let request = ClassAuthGetRequest(url: "https://example.com/secure")

        // When
        let response = await request.request()

        // Then the request is sent without an authorization header
        guard case .success = response else {
            XCTFail("Expected success but got: \(response)")
            return
        }
        XCTAssertEqual(AuthStubProtocol.receivedAuthorizations, [nil])
    }

    func test401OnRequestThatOptedOutOfAuthGivesUpWithoutConsultingTheProvider() async throws {
        // Given a provider with credentials and a request that does not need auth, answered with a 401
        let provider = SpyAuthProvider(headers: [HAuthorizationHeader(key: "Authorization", value: "Bearer token_1")])
        Harbor.setAuthProvider(provider)
        AuthStubProtocol.statusCodes = [401]

        let request = ClassAuthGetRequest(url: "https://example.com/public", needsAuth: false)

        // When
        let response = await request.request()

        // Then the flow gives up with .authNeeded and the provider is never consulted
        guard case .error(let error) = response, case .authNeeded = error else {
            XCTFail("Expected .authNeeded but got: \(response)")
            return
        }
        XCTAssertEqual(provider.headerCallCount, 0)
        XCTAssertEqual(provider.authFailedCount, 0)
        XCTAssertEqual(AuthStubProtocol.receivedAuthorizations, [nil])
    }

    // MARK: - Vary: Authorization Cache Tests

    func testVaryAuthorizationVariantsAreKeyedPerCredential() async throws {
        // Given a custom cache and a server that varies on Authorization, tagging each
        // body with the credential it was fetched with
        await Harbor.clearAllCache()
        Harbor.setDefaultCacheType(.custom(HCache.Configuration(expirationTime: .oneHour)))
        AuthStubProtocol.responseHeaders = ["Vary": "Authorization"]
        AuthStubProtocol.etag = "\"vary-etag\""
        AuthStubProtocol.bodyIncludesAuthorization = true

        let tokenA = HAuthorizationHeader(key: "Authorization", value: "Bearer token_A")
        let tokenB = HAuthorizationHeader(key: "Authorization", value: "Bearer token_B")

        let request = ClassAuthGetRequest(url: "https://example.com/vary")

        // When user A fetches, the response is cached under A's credential
        Harbor.setAuthProvider(SpyAuthProvider(headers: [tokenA]))
        guard case .success(let modelA) = await request.request() else {
            XCTFail("Expected success for the first request")
            return
        }
        XCTAssertEqual(modelA.quote, "Bearer token_A")

        // Then a request with B's credential must not be served A's cached variant: the
        // vary mismatch withholds the validators, so the server answers a full 200
        Harbor.setAuthProvider(SpyAuthProvider(headers: [tokenB]))
        guard case .success(let modelB) = await request.request() else {
            XCTFail("Expected success for the second request")
            return
        }
        XCTAssertEqual(modelB.quote, "Bearer token_B")

        // And repeating B's credential revalidates: the server answers 304 and the
        // cached variant for B is served
        Harbor.setAuthProvider(SpyAuthProvider(headers: [tokenB]))
        guard case .success(let modelBAgain) = await request.request() else {
            XCTFail("Expected success for the revalidation request")
            return
        }
        XCTAssertEqual(modelBAgain.quote, "Bearer token_B")
        XCTAssertEqual(AuthStubProtocol.receivedIfNoneMatch, [nil, nil, "\"vary-etag\""])
    }

    func testCacheReadWithoutExplicitHeaderResolvesItFromTheProvider() async throws {
        // Given a stored Vary: Authorization entry and a provider issuing the same credential
        await Harbor.clearAllCache()
        Harbor.setDefaultCacheType(.custom(HCache.Configuration(expirationTime: .oneHour)))
        let token = HAuthorizationHeader(key: "Authorization", value: "Bearer token_A")
        Harbor.setAuthProvider(SpyAuthProvider(headers: [token]))

        let request = ClassAuthGetRequest(url: "https://example.com/vary-auto")
        try await storeVaryAuthorizationEntry(Data("{\"quote\":\"cached\"}".utf8), for: request, authHeader: token)

        // When the cache is read without an explicit header, the provider's header keys
        // the vary lookup and the entry is served
        let cached = await request.cache()
        XCTAssertEqual(cached?.quote, "cached")
    }

    func testCacheReadWithoutExplicitHeaderMissesWhenProviderCredentialDiffers() async throws {
        // Given a stored Vary: Authorization entry and a provider issuing a different credential
        await Harbor.clearAllCache()
        Harbor.setDefaultCacheType(.custom(HCache.Configuration(expirationTime: .oneHour)))
        let storedToken = HAuthorizationHeader(key: "Authorization", value: "Bearer token_A")
        let otherToken = HAuthorizationHeader(key: "Authorization", value: "Bearer token_B")
        Harbor.setAuthProvider(SpyAuthProvider(headers: [otherToken]))

        let request = ClassAuthGetRequest(url: "https://example.com/vary-auto")
        try await storeVaryAuthorizationEntry(Data("{\"quote\":\"cached\"}".utf8), for: request, authHeader: storedToken)

        // When the cache is read, the vary mismatch must not serve the stored variant
        let cached = await request.cache()
        XCTAssertNil(cached)
    }

    func testCacheReadWithoutExplicitHeaderMissesGracefullyWithoutProvider() async throws {
        // Given a stored Vary: Authorization entry and no configured provider
        await Harbor.clearAllCache()
        Harbor.setDefaultCacheType(.custom(HCache.Configuration(expirationTime: .oneHour)))
        Harbor.setAuthProvider(nil)
        let token = HAuthorizationHeader(key: "Authorization", value: "Bearer token_A")

        let request = ClassAuthGetRequest(url: "https://example.com/vary-auto")
        try await storeVaryAuthorizationEntry(Data("{\"quote\":\"cached\"}".utf8), for: request, authHeader: token)

        // When the cache is read, the lookup proceeds without a header and misses
        let cached = await request.cache()
        XCTAssertNil(cached)
    }

    /// Stores a body as a `Vary: Authorization` cache entry for the given request.
    private func storeVaryAuthorizationEntry(_ data: Data, for request: ClassAuthGetRequest, authHeader: HAuthorizationHeader) async throws {
        let url = try XCTUnwrap(URL(string: request.url))
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Vary": "Authorization"])
        await request.saveCache(data, response: response, authHeader: authHeader)
    }
}
