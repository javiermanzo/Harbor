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
/// of every request it sees.
private final class AuthStubProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _statusCodes: [Int] = [200]
    nonisolated(unsafe) private static var _receivedAuthorizations: [String?] = []

    static var receivedAuthorizations: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return _receivedAuthorizations
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

    static func reset() {
        lock.lock()
        _statusCodes = [200]
        _receivedAuthorizations = []
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
        let index = Self._receivedAuthorizations.count
        Self._receivedAuthorizations.append(request.value(forHTTPHeaderField: "Authorization"))
        let statusCodes = Self._statusCodes
        Self.lock.unlock()

        let statusCode = statusCodes[min(index, statusCodes.count - 1)]
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"quote\":\"ok\"}".utf8))
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
}
