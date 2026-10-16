//
//  HarborWebSocketTests.swift
//  HarborWebSocketTests
//
//  Connection lifecycle against a loopback WebSocket server: handshake, headers, messages,
//  pings, close frames and lost connections.
//

import XCTest
import Network
@testable import Harbor
@testable import HarborWebSocket

@HRequestManagerActor
final class HarborWebSocketTests: XCTestCase {

    private var servers: [LoopbackWebSocketServer] = []

    override func setUp() async throws {
        Harbor.setAuthProvider(nil)
        Harbor.setDefaultHeaderParameters(nil)
        Harbor.setSSLPinningKeys(nil)
        HConfig.shared.customURLSession = nil
        HarborWebSocket.setDefaultPingInterval(nil)
        HRequestManager.connectivityMonitor = FakeConnectivityMonitor(connected: true)
    }

    override func tearDown() async throws {
        servers.forEach { $0.stop() }
        servers.removeAll()
        Harbor.setAuthProvider(nil)
        Harbor.setDefaultHeaderParameters(nil)
        Harbor.setSSLPinningKeys(nil)
        HConfig.shared.customURLSession = nil
        HarborWebSocket.setDefaultPingInterval(nil)
        HRequestManager.connectivityMonitor = HRequestManagerMonitor()
    }

    // MARK: - Handshake

    func testConnectSendsHeadersQueryAndSubprotocols() async throws {
        // Given
        Harbor.setDefaultHeaderParameters(["X-Client": "harbor", "X-Overridden": "default"])
        let server = try await startServer()
        let request = TestSocket(url: server.url(path: "/rooms/{room}"),
                                 pathParameters: ["room": "swift 6"],
                                 queryParameters: ["token": "a+b"],
                                 headerParameters: ["X-Overridden": "request", "X-Request": "1"],
                                 subprotocols: ["chat", "superchat"])

        // When
        let socket = try await request.connect()
        defer { Task { await socket.close() } }

        // Then
        let subprotocol = socket.negotiatedSubprotocol
        XCTAssertEqual(subprotocol, "chat")
        let handshake = try XCTUnwrap(server.handshakes.first)
        XCTAssertEqual(handshake.subprotocols.map { $0.trimmingCharacters(in: .whitespaces) }, ["chat", "superchat"])
        XCTAssertEqual(handshake.headers["x-client"], "harbor")
        XCTAssertEqual(handshake.headers["x-overridden"], "request")
        XCTAssertEqual(handshake.headers["x-request"], "1")
        let state = await socket.state
        XCTAssertEqual(state, .open)
    }

    func testHTTPSchemesAreRewrittenToWebSocketSchemes() async throws {
        // Given
        let server = try await startServer()

        // When
        let socket = try await TestSocket(url: "http://127.0.0.1:\(server.port)/").connect()

        // Then
        let state = await socket.state
        XCTAssertEqual(state, .open)
        XCTAssertEqual(server.handshakes.count, 1)
        await socket.close()

        let url = try HWebSocketManager.webSocketURL(for: TestSocket(url: "https://example.com/socket?a=1"))
        XCTAssertEqual(url.absoluteString, "wss://example.com/socket?a=1")
    }

    func testUnsupportedSchemeFailsWithInvalidURL() async {
        // When
        let error = await connectError(TestSocket(url: "ftp://example.com/socket"))

        // Then
        guard case .invalidURL(let reason) = error else {
            return XCTFail("Expected .invalidURL, got \(String(describing: error))")
        }
        XCTAssertTrue(reason.contains("ftp"), reason)
    }

    func testOfflineFailsWithNoConnection() async throws {
        // Given
        let server = try await startServer()
        HRequestManager.connectivityMonitor = FakeConnectivityMonitor(connected: false)

        // When
        let error = await connectError(TestSocket(url: server.url()))

        // Then
        XCTAssertEqual(error, .noConnection)
        XCTAssertTrue(server.handshakes.isEmpty)
    }

    func testNeedsAuthWithoutProviderFailsBeforeConnecting() async throws {
        // Given
        let server = try await startServer()

        // When
        let error = await connectError(TestSocket(url: server.url(), needsAuth: true))

        // Then
        XCTAssertEqual(error, .authProviderNeeded)
        XCTAssertTrue(server.handshakes.isEmpty)
    }

    func testAuthProviderHeaderIsSentWithTheHandshake() async throws {
        // Given
        let server = try await startServer()
        Harbor.setAuthProvider(RotatingAuthProvider(token: "abc"))

        // When
        let socket = try await TestSocket(url: server.url(), needsAuth: true).connect()
        await socket.close()

        // Then
        XCTAssertEqual(server.handshakes.first?.headers["authorization"], "Bearer abc")
    }

    // MARK: - Messages

    func testReceivesTextAndBinaryMessagesInOrder() async throws {
        // Given
        let server = try await startServer { connection in
            connection.send(text: "one")
            connection.send(data: Data([0x01, 0x02]))
            connection.send(text: "three")
            connection.close(code: .protocolCode(.normalClosure), reason: Data("done".utf8))
        }

        // When
        let socket = try await TestSocket(url: server.url()).connect()
        let result = await drain(socket)

        // Then
        XCTAssertEqual(result.messages, [.text("one"), .data(Data([0x01, 0x02])), .text("three")])
        XCTAssertNil(result.error)
        let state = await socket.state
        XCTAssertEqual(state.closeCode, .normalClosure)
        XCTAssertEqual(state.closeReasonText, "done")
    }

    func testSendsTextBinaryAndJSON() async throws {
        // Given
        let server = try await startServer()
        let socket = try await TestSocket(url: server.url()).connect()

        // When
        try await socket.send("hello")
        try await socket.send(Data([0xAA]))
        try await socket.send(json: ChatEvent(type: "message", text: "hi"))

        // Then
        let connection = try XCTUnwrap(server.connections.first)
        let frames = await connection.waitForFrames(count: 3)
        XCTAssertEqual(frames[0], .text("hello"))
        XCTAssertEqual(frames[1], .data(Data([0xAA])))
        guard case .text(let json) = frames[2] else { return XCTFail("Expected a text frame") }
        XCTAssertEqual(try JSONDecoder().decode(ChatEvent.self, from: Data(json.utf8)), ChatEvent(type: "message", text: "hi"))
        await socket.close()
    }

    func testMessageDecodeHelper() async throws {
        // Given
        let text = HWebSocketMessage.text(#"{"type":"t","text":"x"}"#)
        let data = HWebSocketMessage.data(Data(#"{"type":"t","text":"y"}"#.utf8))

        // Then
        XCTAssertEqual(try text.decode(ChatEvent.self), ChatEvent(type: "t", text: "x"))
        XCTAssertEqual(try data.decode(ChatEvent.self), ChatEvent(type: "t", text: "y"))
        XCTAssertThrowsError(try HWebSocketMessage.text("nope").decode(ChatEvent.self)) { error in
            guard case HWebSocketError.codable(let model, _) = error else { return XCTFail("Expected .codable, got \(error)") }
            XCTAssertEqual(model, "ChatEvent")
        }
    }

    func testSendJSONEncodingFailureThrowsCodable() async throws {
        // Given
        let server = try await startServer()
        let socket = try await TestSocket(url: server.url()).connect()
        defer { Task { await socket.close() } }

        // When / Then: Double.nan cannot be encoded as JSON
        do {
            try await socket.send(json: [Double.nan])
            XCTFail("Expected send(json:) to throw")
        } catch {
            guard case .codable = error else { return XCTFail("Expected .codable, got \(error)") }
        }
    }

    func testMessagesAreBufferedUntilIterated() async throws {
        // Given a server that sends before the app starts reading
        let server = try await startServer { connection in
            for index in 0 ..< 50 {
                connection.send(text: "\(index)")
            }
            connection.close()
        }
        let socket = try await TestSocket(url: server.url()).connect()
        try await Task.sleep(nanoseconds: 300_000_000)

        // When
        let result = await drain(socket)

        // Then
        XCTAssertEqual(result.messages.count, 50)
        XCTAssertEqual(result.messages.first, .text("0"))
        XCTAssertEqual(result.messages.last, .text("49"))
    }

    // MARK: - Closing

    func testCloseSendsCloseFrameAndFinishesStream() async throws {
        // Given
        let server = try await startServer()
        let socket = try await TestSocket(url: server.url()).connect()
        let connection = try XCTUnwrap(server.connections.first)

        // When
        await socket.close(code: .goingAway, reason: Data("bye".utf8))

        // Then
        let state = await socket.state
        XCTAssertEqual(state, .closed(code: .goingAway, reason: Data("bye".utf8)))
        let result = await drain(socket)
        XCTAssertTrue(result.messages.isEmpty)
        XCTAssertNil(result.error)
        let frames = await connection.waitForFrames(count: 1)
        XCTAssertEqual(frames.last, .close(code: .protocolCode(.goingAway)))

        // And the connection is closed for good
        do {
            try await socket.send("late")
            XCTFail("Expected send() to throw")
        } catch {
            XCTAssertEqual(error, .notConnected)
        }
        await socket.close()   // idempotent
        let stillClosed = await socket.state
        XCTAssertEqual(stillClosed.closeCode, .goingAway)
    }

    func testServerCloseFinishesStreamWithCode() async throws {
        // Given
        let server = try await startServer { connection in
            connection.send(text: "last")
            connection.close(code: .protocolCode(.policyViolation), reason: Data("banned".utf8))
        }

        // When
        let socket = try await TestSocket(url: server.url()).connect()
        let result = await drain(socket)

        // Then
        XCTAssertEqual(result.messages, [.text("last")])
        XCTAssertNil(result.error)
        let state = await socket.state
        XCTAssertEqual(state, .closed(code: .policyViolation, reason: Data("banned".utf8)))
    }

    func testDroppedConnectionThrowsFromStream() async throws {
        // Given a server that cuts the TCP connection without a close frame
        let server = try await startServer { connection in
            connection.send(text: "before")
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                connection.drop()
            }
        }

        // When
        let socket = try await TestSocket(url: server.url()).connect()
        let result = await drain(socket)

        // Then
        XCTAssertEqual(result.messages, [.text("before")])
        let error = try XCTUnwrap(result.error)
        switch error {
        case .networkFailure, .unknown, .cannotConnectToHost:
            break
        default:
            XCTFail("Expected a transport error, got \(error)")
        }
        let state = await socket.state
        XCTAssertEqual(state, .closed(code: .abnormalClosure, reason: nil))
    }

    func testCancellingTheConsumerClosesTheConnection() async throws {
        // Given
        let server = try await startServer()
        let socket = try await TestSocket(url: server.url()).connect()
        let connection = try XCTUnwrap(server.connections.first)
        let consumer = Task {
            for try await _ in socket.messages {}
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        // When
        consumer.cancel()
        _ = await consumer.result

        // Then
        let closed = await waitUntil { await socket.state != .open }
        XCTAssertTrue(closed)
        let state = await socket.state
        XCTAssertEqual(state.closeCode, .goingAway)
        let frames = await connection.waitForFrames(count: 1)
        XCTAssertEqual(frames.last, .close(code: .protocolCode(.goingAway)))
    }

    func testLeavingTheLoopWithBreakDoesNotCloseTheConnection() async throws {
        // Given a server that sends two messages
        let server = try await startServer { connection in
            connection.send(text: "one")
            connection.send(text: "two")
        }
        let socket = try await TestSocket(url: server.url()).connect()

        // When the app stops iterating after the first message
        for try await message in socket.messages {
            XCTAssertEqual(message, .text("one"))
            break
        }
        try await Task.sleep(nanoseconds: 300_000_000)

        // Then the connection is still open and the next iteration continues with the buffered message
        let state = await socket.state
        XCTAssertEqual(state, .open)
        for try await message in socket.messages {
            XCTAssertEqual(message, .text("two"))
            break
        }
        await socket.close()
    }

    func testMessageLargerThanMaximumSizeFailsTheConnection() async throws {
        // Given
        let server = try await startServer { connection in
            connection.send(data: Data(repeating: 0x42, count: 2048))
        }

        // When
        let socket = try await TestSocket(url: server.url(), maximumMessageSize: 512).connect()
        let result = await drain(socket)

        // Then
        XCTAssertTrue(result.messages.isEmpty)
        XCTAssertEqual(result.error, .messageTooBig)
        let state = await socket.state
        XCTAssertEqual(state, .closed(code: .abnormalClosure, reason: nil))
    }

    func testIdleConnectionOutlivesTheHandshakeTimeout() async throws {
        // Given a 1 s handshake timeout and no traffic for longer than that
        let server = try await startServer()
        let socket = try await TestSocket(url: server.url(), timeoutInterval: 1).connect()
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // When
        try await socket.send("still here")

        // Then
        let connection = try XCTUnwrap(server.connections.first)
        let frames = await connection.waitForFrames(count: 1)
        XCTAssertEqual(frames.first, .text("still here"))
        let state = await socket.state
        XCTAssertEqual(state, .open)
        await socket.close()
    }

    // MARK: - Pings

    func testManualPingReachesTheServer() async throws {
        // Given
        let server = try await startServer()
        let socket = try await TestSocket(url: server.url()).connect()

        // When
        try await socket.ping()

        // Then
        let connection = try XCTUnwrap(server.connections.first)
        let frames = await connection.waitForFrames(count: 1)
        XCTAssertEqual(frames.first, .ping)
        await socket.close()
    }

    func testKeepAlivePingsAreSentAtTheConfiguredInterval() async throws {
        // Given
        let server = try await startServer()
        let socket = try await TestSocket(url: server.url(), pingInterval: 0.1).connect()

        // Then
        let connection = try XCTUnwrap(server.connections.first)
        let frames = await connection.waitForFrames(count: 3)
        XCTAssertTrue(frames.allSatisfy { $0 == .ping }, "\(frames)")
        let state = await socket.state
        XCTAssertEqual(state, .open)
        await socket.close()
    }

    func testDefaultPingIntervalAppliesWhenTheRequestSetsNone() async throws {
        // Given
        let server = try await startServer()
        HarborWebSocket.setDefaultPingInterval(0.1)
        let socket = try await TestSocket(url: server.url()).connect()

        // Then
        let connection = try XCTUnwrap(server.connections.first)
        let frames = await connection.waitForFrames(count: 2)
        XCTAssertTrue(frames.allSatisfy { $0 == .ping }, "\(frames)")
        await socket.close()
    }

    func testManualPingOnADeadLinkThrowsPingTimeoutAndClosesTheConnection() async throws {
        // Given a server that never answers pings and a short ping interval (the ping timeout)
        let server = try await startServer(autoReplyPing: false)
        let socket = try await TestSocket(url: server.url(), pingInterval: 0.3).connect()

        // When
        do {
            try await socket.ping()
            XCTFail("Expected ping() to throw")
        } catch {
            XCTAssertEqual(error, .pingTimeout)
        }

        // Then
        let result = await drain(socket)
        XCTAssertEqual(result.error, .pingTimeout)
        let state = await socket.state
        XCTAssertEqual(state, .closed(code: .abnormalClosure, reason: nil))
    }

    func testCancellingAPingDoesNotCloseTheConnection() async throws {
        // Given a server that never answers pings
        let server = try await startServer(autoReplyPing: false)
        let socket = try await TestSocket(url: server.url(), pingInterval: 5).connect()

        // When the caller of ping() is cancelled while waiting for the pong
        let pinging = Task { () -> HWebSocketError? in
            do throws(HWebSocketError) {
                try await socket.ping()
                return nil
            } catch {
                return error
            }
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        pinging.cancel()
        let error = await pinging.value

        // Then the call reports the cancellation and the healthy connection stays open
        XCTAssertEqual(error, HWebSocketError.cancelled)
        let state = await socket.state
        XCTAssertEqual(state, .open)
        await socket.close()
    }

    func testServerCloseWhileAPingIsInFlightReportsTheCloseCode() async throws {
        // Given a server that never answers pings and closes while a keep-alive ping is pending
        let server = try await startServer(autoReplyPing: false) { connection in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) {
                connection.close(code: .protocolCode(.policyViolation), reason: Data("banned".utf8))
            }
        }
        let socket = try await TestSocket(url: server.url(), pingInterval: 0.25).connect()

        // When
        let result = await drain(socket)

        // Then: the close frame wins over the ping failure
        XCTAssertNil(result.error)
        let state = await socket.state
        XCTAssertEqual(state, .closed(code: .policyViolation, reason: Data("banned".utf8)))
    }

    func testNonFinitePingIntervalDisablesPings() async throws {
        // Given
        let server = try await startServer()

        // When
        let socket = try await TestSocket(url: server.url(), pingInterval: .infinity).connect()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then: no trap, no pings
        let state = await socket.state
        XCTAssertEqual(state, .open)
        XCTAssertTrue(server.connections.first?.received.isEmpty ?? true)
        await socket.close()
    }

    func testMissingPongClosesTheConnectionWithPingTimeout() async throws {
        // Given a server that never answers pings
        let server = try await startServer(autoReplyPing: false)
        let socket = try await TestSocket(url: server.url(), pingInterval: 0.2).connect()

        // When
        let result = await drain(socket)

        // Then
        XCTAssertEqual(result.error, .pingTimeout)
        let state = await socket.state
        XCTAssertEqual(state, .closed(code: .abnormalClosure, reason: nil))
    }

    // MARK: - Logging

    func testDebugRequestLogsWithoutAffectingTheConnection() async throws {
        // Given
        let server = try await startServer { connection in
            connection.send(text: #"{"token":"secret","ok":true}"#)
            // Close only after the client's message arrived, so the send below is not racing the close.
            Task {
                _ = await connection.waitForFrames(count: 1)
                connection.close()
            }
        }
        Harbor.setLoggingEnabled(true)
        defer { Harbor.setLoggingEnabled(HBuild.isDebug) }

        // When
        let socket = try await DebugTestSocket(url: server.url(), headerParameters: ["Authorization": "Bearer x"]).connect()
        try await socket.send(json: ChatEvent(type: "login", text: "p"))
        let result = await drain(socket)

        // Then
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertNil(result.error)
    }

    // MARK: - Session Pool

    func testResourceTimeoutDoesNotApplyToConnections() async throws {
        // Given a whole-transfer timeout meant for REST transfers
        Harbor.setDefaultResourceTimeoutInterval(1)
        defer { Harbor.setDefaultResourceTimeoutInterval(nil) }
        let server = try await startServer()
        let socket = try await TestSocket(url: server.url()).connect()
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // When
        try await socket.send("outlived the resource timeout")

        // Then
        let connection = try XCTUnwrap(server.connections.first)
        let frames = await connection.waitForFrames(count: 1)
        XCTAssertEqual(frames.first, .text("outlived the resource timeout"))
        let state = await socket.state
        XCTAssertEqual(state, .open)
        await socket.close()
    }

    func testConnectionHoldsItsSessionLeaseUntilClosed() async throws {
        // Given
        let server = try await startServer()
        let socket = try await TestSocket(url: server.url()).connect()

        // When the session-affecting configuration changes while the socket is open
        Harbor.setHTTPShouldHandleCookies(true)
        defer { Harbor.setHTTPShouldHandleCookies(false) }

        // Then the retired session is kept alive by the lease and the socket keeps working
        XCTAssertEqual(HRequestManager.retiredURLSessionCount, 1)
        try await socket.send("still open")
        let connection = try XCTUnwrap(server.connections.first)
        let frames = await connection.waitForFrames(count: 1)
        XCTAssertEqual(frames.first, .text("still open"))

        await socket.close()
        let released = await waitUntil { await HRequestManager.retiredURLSessionCount == 0 }
        XCTAssertTrue(released)
    }

    // MARK: - Helpers

    private func startServer(autoReplyPing: Bool = true, onConnection: @escaping @Sendable (LoopbackWebSocketServer.Connection) -> Void = { _ in }) async throws -> LoopbackWebSocketServer {
        let server = try LoopbackWebSocketServer(autoReplyPing: autoReplyPing, onConnection: onConnection)
        try await server.start()
        servers.append(server)
        return server
    }
}
