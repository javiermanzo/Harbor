//
//  HarborMockTests.swift
//  Harbor
//
//  Created by Javier Manzo on 12/11/2024.
//

import XCTest
@testable import Harbor

/// Records whether a slow decode is in progress, shared between the decoding request and the test.
private final class DecodeProbe: @unchecked Sendable {
    static let shared = DecodeProbe()
    private let lock = NSLock()
    private var _isDecoding = false

    var isDecoding: Bool {
        get { lock.withLock { _isDecoding } }
        set { lock.withLock { _isDecoding = newValue } }
    }
}

/// Request whose decoding blocks its thread for a while, to observe where decoding runs.
private struct SlowDecodingRequest: HGetRequestProtocol {
    typealias Model = MockModel
    let url = "https://example.com/slow-decode"

    func parseData<T: Codable>(data: Data, model: T.Type) throws -> T {
        DecodeProbe.shared.isDecoding = true
        defer { DecodeProbe.shared.isDecoding = false }
        Thread.sleep(forTimeInterval: 0.8)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Auth provider that always issues the same header and counts `authFailed()` calls.
@HRequestManagerActor
private final class CountingAuthProvider: HAuthProviderProtocol {
    private(set) var authFailedCount = 0

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        HAuthorizationHeader(key: "Authorization", value: "Bearer token")
    }

    func authFailed() async {
        authFailedCount += 1
    }
}

/// POST request with a retry policy, for mocked retry classification.
private struct RetryingMockPostRequest: HPostRequestProtocol, @unchecked Sendable {
    var url = "https://example.com/mocked-post"
    var bodyParameters: [String: Any]?
    var retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 2, baseDelay: 0.01, multiplier: 1, jitter: 0...0)
}

@HRequestManagerActor
final class HarborMockTests: XCTestCase {

    override func setUp() async throws {
        Harbor.removeAllMocks()
        Harbor.setMocksEnabled(nil)
    }

    override func tearDown() async throws {
        Harbor.removeAllMocks()
        Harbor.setMocksEnabled(nil)
        Harbor.setAuthProvider(nil)
    }

    func testSuccessMock() async throws {
        let json = """
            {"quote":"For me to say I wasn't a genius I'd just be lying to you and to myself"}
            """
        let mock = HMock(request: MockGetRequest<MockModel>.self, statusCode: 200, jsonResponse: json)
        Harbor.register(mock: mock)

        let response = await MockGetRequest<MockModel>(url: "https://api.kanye.rest/").request()

        switch response {
        case .success(let result):
            XCTAssertNotNil(result)
        default:
            XCTFail("Expected success but got an unexpected result")
        }
    }

    func testAuthenticationErrorMock() async throws {
        let mock = HMock(request: MockGetRequest<MockModel>.self, statusCode: 401, error: .authNeeded)
        Harbor.register(mock: mock)

        let response = await MockGetRequest<MockModel>(url: "https://api.kanye.rest/").request()

        switch response {
        case .error(let error):
            guard case .authNeeded = error else {
                return XCTFail("Expected authNeeded but got: \(error)")
            }
        default:
            XCTFail("Expected error authNeeded but got: \(response)")
        }
    }

    func testAddAndRemoveMock() async throws {
        let successMock = HMock(request: MockGetRequest<MockModel>.self, statusCode: 200, jsonResponse: """
            {"quote":"Success after mock removal"}
            """)

        // Before registering, no mock is present for the request type.
        XCTAssertFalse(Harbor.isMockRegistered(MockGetRequest<MockModel>.self))

        Harbor.register(mock: successMock)
        XCTAssertTrue(Harbor.isMockRegistered(MockGetRequest<MockModel>.self))

        // Removing the mock clears the registration.
        Harbor.remove(mock: successMock)
        XCTAssertFalse(Harbor.isMockRegistered(MockGetRequest<MockModel>.self))
    }

    func testRemoveAllMocksClearsRegistration() async throws {
        Harbor.register(mock: HMock(request: MockGetRequest<MockModel>.self, statusCode: 200))
        Harbor.register(mock: HMock(request: MockGetRequestWithRetries<MockModel>.self, statusCode: 200))
        XCTAssertEqual(Harbor.isMockRegistered(MockGetRequest<MockModel>.self), true)
        XCTAssertEqual(Harbor.isMockRegistered(MockGetRequestWithRetries<MockModel>.self), true)

        Harbor.removeAllMocks()
        XCTAssertEqual(Harbor.isMockRegistered(MockGetRequest<MockModel>.self), false)
        XCTAssertEqual(Harbor.isMockRegistered(MockGetRequestWithRetries<MockModel>.self), false)
    }

    // MARK: - Call counting

    func testCallCountTracksResolutions() async throws {
        Harbor.setMocksEnabled(true)
        Harbor.register(mock: HMock(request: MockGetRequest<MockModel>.self, statusCode: 200, jsonResponse: """
            {"quote":"counted"}
            """))

        XCTAssertEqual(Harbor.mockCallCount(for: MockGetRequest<MockModel>.self), 0)

        _ = await MockGetRequest<MockModel>(url: "https://example.com").request()
        _ = await MockGetRequest<MockModel>(url: "https://example.com").request()

        XCTAssertEqual(Harbor.mockCallCount(for: MockGetRequest<MockModel>.self), 2)
    }

    // MARK: - Sequenced mocks

    func testSequencePlaysResponsesInOrderThenRepeats() async throws {
        Harbor.setMocksEnabled(true)
        Harbor.registerMockSequence(HMockSequence(request: MockGetRequest<MockModel>.self, responses: [
            .init(statusCode: 401, error: .authNeeded),
            .init(statusCode: 200, jsonResponse: """
            {"quote":"then-success"}
            """)
        ]))

        // First resolution: the 401 response.
        let first = await MockGetRequest<MockModel>(url: "https://example.com").request()
        guard case .error(let firstError) = first, case .authNeeded = firstError else {
            return XCTFail("Expected authNeeded first but got: \(first)")
        }

        // Second resolution: the 200 response.
        let second = await MockGetRequest<MockModel>(url: "https://example.com").request()
        guard case .success(let model) = second else {
            return XCTFail("Expected success second but got: \(second)")
        }
        XCTAssertEqual(model.quote, "then-success")

        // Subsequent resolutions repeat the last response.
        let third = await MockGetRequest<MockModel>(url: "https://example.com").request()
        if case .error = third {
            XCTFail("Expected the sequence to repeat its last (success) response but got: \(third)")
        }
    }

    // MARK: - Mocks enabled override

    func testMocksEnabledOverrideForcesMocksOff() async throws {
        Harbor.register(mock: HMock(request: MockGetRequest<MockModel>.self, statusCode: 200, jsonResponse: """
            {"quote":"ignored"}
            """))
        Harbor.setMocksEnabled(false)

        // With mocks forced off, a registered mock is not served: the request reaches the
        // connectivity pre-check and, with no network stub, surfaces a deterministic error.
        let response = await MockGetRequest<MockModel>(url: "https://example.com").request()
        if case .success = response {
            XCTFail("Expected the mock to be ignored while mocks are disabled but got success")
        }
    }

    // MARK: - Per-attempt resolution

    func testSequenceAdvancesAcrossRetries() async throws {
        // Given a sequence that fails with a 500 once, then succeeds, and a request with retries
        Harbor.registerMockSequence(HMockSequence(request: MockGetRequest<MockModel>.self, responses: [
            .init(statusCode: 500),
            .init(statusCode: 200, jsonResponse: """
            {"quote":"after-retry"}
            """)
        ]))
        let policy = HRetryPolicy(maxRetries: 2, baseDelay: 0.01, multiplier: 1, jitter: 0...0)

        // When
        let response = await MockGetRequest<MockModel>(retryPolicy: policy, url: "https://example.com").request()

        // Then the retry resolves the next mock in the sequence
        guard case .success(let model) = response else {
            return XCTFail("Expected success after the retry but got: \(response)")
        }
        XCTAssertEqual(model.quote, "after-retry")
        XCTAssertEqual(Harbor.mockCallCount(for: MockGetRequest<MockModel>.self), 2)
    }

    func testSequenceAdvancesAcross401ReAttempt() async throws {
        // Given a sequence answering 401 then 200, and an auth provider
        let provider = CountingAuthProvider()
        Harbor.setAuthProvider(provider)
        Harbor.registerMockSequence(HMockSequence(request: MockGetRequest<MockModel>.self, responses: [
            .init(statusCode: 401),
            .init(statusCode: 200, jsonResponse: """
            {"quote":"after-auth"}
            """)
        ]))

        // When
        let response = await MockGetRequest<MockModel>(needsAuth: true, url: "https://example.com").request()

        // Then the auth re-attempt resolves the next mock
        guard case .success(let model) = response else {
            return XCTFail("Expected success after the auth re-attempt but got: \(response)")
        }
        XCTAssertEqual(model.quote, "after-auth")
        XCTAssertEqual(provider.authFailedCount, 1)
        XCTAssertEqual(Harbor.mockCallCount(for: MockGetRequest<MockModel>.self), 2)
    }

    func testMockedTransportErrorIsRetried() async throws {
        // Given a sequence that times out once, then succeeds, and a request with retries
        Harbor.registerMockSequence(HMockSequence(request: MockGetRequest<MockModel>.self, responses: [
            .init(statusCode: 0, error: .timeout),
            .init(statusCode: 200, jsonResponse: """
            {"quote":"after-timeout"}
            """)
        ]))
        let policy = HRetryPolicy(maxRetries: 2, baseDelay: 0.01, multiplier: 1, jitter: 0...0)

        // When
        let response = await MockGetRequest<MockModel>(retryPolicy: policy, url: "https://example.com").request()

        // Then the mocked timeout goes through the retry policy like a real one
        guard case .success(let model) = response else {
            return XCTFail("Expected success after the retry but got: \(response)")
        }
        XCTAssertEqual(model.quote, "after-timeout")
        XCTAssertEqual(Harbor.mockCallCount(for: MockGetRequest<MockModel>.self), 2)
    }

    func testMockedTimeoutOnNonIdempotentRequestIsNotRetriedByDefault() async throws {
        // Given a POST whose first mocked attempt times out
        Harbor.registerMockSequence(HMockSequence(request: RetryingMockPostRequest.self, responses: [
            .init(statusCode: 0, error: .timeout),
            .init(statusCode: 200)
        ]))

        // When
        let response = await RetryingMockPostRequest().request()

        // Then the timeout may have reached the server, so the POST is not repeated
        guard case .error(let error) = response, case .timeout = error else {
            return XCTFail("Expected .timeout but got: \(response)")
        }
        XCTAssertEqual(Harbor.mockCallCount(for: RetryingMockPostRequest.self), 1)
    }

    func testMockedPreConnectionErrorOnNonIdempotentRequestIsRetried() async throws {
        // Given a POST whose first mocked attempt cannot reach the host
        Harbor.registerMockSequence(HMockSequence(request: RetryingMockPostRequest.self, responses: [
            .init(statusCode: 0, error: .cannotConnectToHost),
            .init(statusCode: 200)
        ]))

        // When
        let response = await RetryingMockPostRequest().request()

        // Then the request never reached the server, so it is retried
        guard case .success = response else {
            return XCTFail("Expected success after the retry but got: \(response)")
        }
        XCTAssertEqual(Harbor.mockCallCount(for: RetryingMockPostRequest.self), 2)
    }

    // MARK: - Decoding isolation

    func testDecodingDoesNotBlockTheRequestManagerActor() async throws {
        // Given a mocked response whose decoding blocks its thread
        Harbor.register(mock: HMock(request: SlowDecodingRequest.self, statusCode: 200, jsonResponse: """
            {"quote":"decoded"}
            """))
        let task = Task.detached { await SlowDecodingRequest().request() }

        // When the decode is running
        let waitStart = Date()
        while !DecodeProbe.shared.isDecoding, Date().timeIntervalSince(waitStart) < 5 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(DecodeProbe.shared.isDecoding, "The decode never started")

        // Then the actor stays responsive: hopping onto it does not wait for the decode
        let hopStart = Date()
        await Self.touchActor()
        XCTAssertLessThan(Date().timeIntervalSince(hopStart), 0.4)

        guard case .success(let model) = await task.value else {
            return XCTFail("Expected the slow decode to succeed")
        }
        XCTAssertEqual(model.quote, "decoded")
    }

    /// Hops onto `HRequestManagerActor` from a nonisolated context.
    nonisolated private static func touchActor() async {
        await HRequestManagerActor.shared.run {}
    }
}

private extension HRequestManagerActor {
    /// Runs the given closure on the actor.
    func run(_ body: @Sendable () -> Void) {
        body()
    }
}
