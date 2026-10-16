//
//  HarborWebSocketHandshakeTests.swift
//  HarborWebSocketTests
//
//  Failed handshakes: HTTP statuses, the 401 auth refresh flow, retry policies, timeouts,
//  cancellation and TLS.
//

import XCTest
import Network
@testable import Harbor
@testable import HarborWebSocket

@HRequestManagerActor
final class HarborWebSocketHandshakeTests: XCTestCase {

    /// A syntactically valid pin (base64 of 32 zero bytes) that matches nothing.
    private let wrongPin = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

    private var responders: [LoopbackHTTPResponder] = []
    private var servers: [LoopbackWebSocketServer] = []

    override func setUp() async throws {
        Harbor.setAuthProvider(nil)
        Harbor.setSSLPinningKeys(nil)
        HConfig.shared.customURLSession = nil
        HRequestManager.connectivityMonitor = FakeConnectivityMonitor(connected: true)
    }

    override func tearDown() async throws {
        responders.forEach { $0.stop() }
        responders.removeAll()
        servers.forEach { $0.stop() }
        servers.removeAll()
        Harbor.setAuthProvider(nil)
        Harbor.setSSLPinningKeys(nil)
        HConfig.shared.customURLSession = nil
        HRequestManager.connectivityMonitor = HRequestManagerMonitor()
    }

    // MARK: - Request Line

    func testPathAndQueryParametersAreEncodedInTheHandshake() async throws {
        // Given
        let responder = try await startResponder { _ in .reply(LoopbackHTTPReply(statusCode: 404)) }
        let request = TestSocket(url: responder.url(path: "/rooms/{room}"),
                                 pathParameters: ["room": "swift 6/beta"],
                                 queryParameters: ["token": "a+b", "a": "1"])

        // When
        _ = await connectError(request)

        // Then
        XCTAssertEqual(responder.receivedRequests.first?.requestLine, "GET /rooms/swift%206%2Fbeta?a=1&token=a%2Bb HTTP/1.1")
        XCTAssertEqual(responder.receivedRequests.first?.headers["upgrade"]?.lowercased(), "websocket")
    }

    // MARK: - HTTP Statuses

    func testNon101StatusFailsWithHandshakeFailed() async throws {
        // Given
        let responder = try await startResponder { _ in .reply(LoopbackHTTPReply(statusCode: 404)) }

        // When
        let error = await connectError(TestSocket(url: responder.url()))

        // Then
        XCTAssertEqual(error, .handshakeFailed(statusCode: 404))
        XCTAssertEqual(responder.receivedRequests.count, 1)
    }

    func testRetryableStatusIsRetriedPerPolicy() async throws {
        // Given
        let responder = try await startResponder { _ in .reply(LoopbackHTTPReply(statusCode: 503, headers: ["Retry-After": "0"])) }
        let policy = HRetryPolicy(maxRetries: 2, baseDelay: 0, jitter: 0...0)

        // When
        let error = await connectError(TestSocket(url: responder.url(), retryPolicy: policy))

        // Then: initial attempt + 2 retries
        XCTAssertEqual(error, .handshakeFailed(statusCode: 503))
        XCTAssertEqual(responder.receivedRequests.count, 3)
    }

    func testRetryableStatusRecoversWhenTheServerComesBack() async throws {
        // Given a front that answers 503 once, then relays to the WebSocket server
        let server = try await startServer()
        let counter = HLockedState(0)
        let responder = try await startResponder { _ in
            let attempt = counter.withLock { count -> Int in
                count += 1
                return count
            }
            return attempt == 1 ? .reply(LoopbackHTTPReply(statusCode: 503)) : .forward(port: server.port)
        }
        let policy = HRetryPolicy(maxRetries: 2, baseDelay: 0, jitter: 0...0)

        // When
        let socket = try await TestSocket(url: responder.url(), retryPolicy: policy).connect()

        // Then
        let state = await socket.state
        XCTAssertEqual(state, .open)
        XCTAssertEqual(responder.receivedRequests.count, 2)
        XCTAssertEqual(server.handshakes.count, 1)
        await socket.close()
    }

    func testNonRetryableStatusIsNotRetried() async throws {
        // Given
        let responder = try await startResponder { _ in .reply(LoopbackHTTPReply(statusCode: 403)) }
        let policy = HRetryPolicy(maxRetries: 2, baseDelay: 0, jitter: 0...0)

        // When
        let error = await connectError(TestSocket(url: responder.url(), retryPolicy: policy))

        // Then
        XCTAssertEqual(error, .handshakeFailed(statusCode: 403))
        XCTAssertEqual(responder.receivedRequests.count, 1)
    }

    func testRetryAfterLongerThanMaxDelayStopsRetrying() async throws {
        // Given
        let responder = try await startResponder { _ in .reply(LoopbackHTTPReply(statusCode: 429, headers: ["Retry-After": "3600"])) }
        let policy = HRetryPolicy(maxRetries: 2, baseDelay: 0, jitter: 0...0)

        // When
        let error = await connectError(TestSocket(url: responder.url(), retryPolicy: policy))

        // Then
        XCTAssertEqual(error, .handshakeFailed(statusCode: 429))
        XCTAssertEqual(responder.receivedRequests.count, 1)
    }

    // MARK: - Authentication

    func testUnauthorizedHandshakeIsRetriedWithRefreshedCredentials() async throws {
        // Given a front that rejects the stale token with 401 and relays the refreshed one
        let provider = RotatingAuthProvider()
        Harbor.setAuthProvider(provider)
        let server = try await startServer()
        let responder = try await startResponder { request in
            request.headers["authorization"] == "Bearer token-0" ? .reply(LoopbackHTTPReply(statusCode: 401)) : .forward(port: server.port)
        }

        // When
        let socket = try await TestSocket(url: responder.url(), needsAuth: true).connect()

        // Then: authFailed() ran once and the second attempt carried the new token
        let state = await socket.state
        XCTAssertEqual(state, .open)
        let refreshCount = await provider.refreshCount
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(responder.receivedRequests.map { $0.headers["authorization"] }, ["Bearer token-0", "Bearer token-1"])
        XCTAssertEqual(server.handshakes.first?.headers["authorization"], "Bearer token-1")
        await socket.close()
    }

    func testUnauthorizedHandshakeWithStaticCredentialsFailsWithAuthNeeded() async throws {
        // Given
        let provider = StaticAuthProvider()
        Harbor.setAuthProvider(provider)
        let responder = try await startResponder { _ in .reply(LoopbackHTTPReply(statusCode: 401)) }

        // When
        let error = await connectError(TestSocket(url: responder.url(), needsAuth: true))

        // Then: authFailed() is called exactly once and no retry is possible
        XCTAssertEqual(error, .authNeeded)
        let refreshCount = await provider.refreshCount
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(responder.receivedRequests.count, 1)
    }

    func testUnauthorizedHandshakeRejectedTwiceFailsWithAuthNeeded() async throws {
        // Given a server that rejects every token
        let provider = RotatingAuthProvider()
        Harbor.setAuthProvider(provider)
        let responder = try await startResponder { _ in .reply(LoopbackHTTPReply(statusCode: 401)) }

        // When
        let error = await connectError(TestSocket(url: responder.url(), needsAuth: true))

        // Then: one refresh, one re-sent handshake, then .authNeeded
        XCTAssertEqual(error, .authNeeded)
        let refreshCount = await provider.refreshCount
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(responder.receivedRequests.count, 2)
    }

    func testUnauthorizedHandshakeWithoutNeedsAuthFailsWithoutCallingTheProvider() async throws {
        // Given
        let provider = RotatingAuthProvider()
        Harbor.setAuthProvider(provider)
        let responder = try await startResponder { _ in .reply(LoopbackHTTPReply(statusCode: 401)) }

        // When
        let error = await connectError(TestSocket(url: responder.url(), needsAuth: false))

        // Then
        XCTAssertEqual(error, .authNeeded)
        let refreshCount = await provider.refreshCount
        XCTAssertEqual(refreshCount, 0)
        XCTAssertNil(responder.receivedRequests.first?.headers["authorization"])
    }

    // MARK: - Transport Failures

    func testConnectionRefusedFailsWithCannotConnectToHost() async throws {
        // Given a port nobody listens on
        let responder = try await startResponder { _ in .ignore }
        let port = responder.port
        responder.stop()

        // When
        let error = await connectError(TestSocket(url: "ws://127.0.0.1:\(port)/"))

        // Then
        XCTAssertEqual(error, .cannotConnectToHost)
    }

    func testConnectionRefusedIsRetriedPerPolicy() async throws {
        // Given
        let responder = try await startResponder { _ in .ignore }
        let port = responder.port
        responder.stop()
        let policy = HRetryPolicy(maxRetries: 1, baseDelay: 0, jitter: 0...0)
        let started = Date()

        // When
        let error = await connectError(TestSocket(url: "ws://127.0.0.1:\(port)/", retryPolicy: policy))

        // Then
        XCTAssertEqual(error, .cannotConnectToHost)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testHandshakeTimeoutFailsWithTimeout() async throws {
        // Given a responder that never answers
        let responder = try await startResponder { _ in .ignore }

        // When
        let error = await connectError(TestSocket(url: responder.url(), timeoutInterval: 0.5))

        // Then
        XCTAssertEqual(error, .timeout)
    }

    func testCancellingConnectFailsWithCancelled() async throws {
        // Given a responder that never answers
        let responder = try await startResponder { _ in .ignore }
        let request = TestSocket(url: responder.url(), timeoutInterval: 10)

        // When
        let connecting = Task {
            await connectError(request)
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        connecting.cancel()
        let error = await connecting.value

        // Then
        XCTAssertEqual(error, .cancelled)
    }

    // MARK: - TLS

    func testPinningMismatchFailsWithCertificate() async throws {
        // Given a wss server presenting the self-signed test certificate and non-matching pins
        let identity = try await TestIdentity.load()
        let server = try LoopbackWebSocketServer(identity: identity.identity)
        try await server.start()
        servers.append(server)
        Harbor.setSSLPinningKeys([wrongPin])
        let policy = HRetryPolicy(maxRetries: 2, baseDelay: 0, jitter: 0...0)

        // When
        let error = await connectError(TestSocket(url: server.url(secure: true), retryPolicy: policy))

        // Then: reported as a certificate error and never retried
        XCTAssertEqual(error, .certificate)
        XCTAssertTrue(server.handshakes.isEmpty)
    }

    func testUntrustedCertificateWithoutPinsFailsWithCertificate() async throws {
        // Given
        let identity = try await TestIdentity.load()
        let server = try LoopbackWebSocketServer(identity: identity.identity)
        try await server.start()
        servers.append(server)

        // When
        let error = await connectError(TestSocket(url: server.url(secure: true)))

        // Then
        XCTAssertEqual(error, .certificate)
    }

    // MARK: - Helpers

    private func startResponder(handler: @escaping @Sendable (LoopbackHTTPRequest) -> LoopbackHTTPAction) async throws -> LoopbackHTTPResponder {
        let responder = try LoopbackHTTPResponder(handler: handler)
        try await responder.start()
        responders.append(responder)
        return responder
    }

    private func startServer() async throws -> LoopbackWebSocketServer {
        let server = try LoopbackWebSocketServer()
        try await server.start()
        servers.append(server)
        return server
    }
}
