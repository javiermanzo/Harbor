//
//  TestSupport.swift
//  HarborWebSocketTests
//
//  Shared fixtures: request types, auth providers, a fake connectivity monitor and the
//  loopback TLS identity.
//

import Foundation
import XCTest
@testable import HarborCore
@testable import HarborWebSocket

/// A configurable WebSocket request.
struct TestSocket: HWebSocketRequestProtocol {
    var url: String
    var pathParameters: [String: String]?
    var queryParameters: [String: String]?
    var headerParameters: [String: String]?
    var subprotocols: [String] = []
    var needsAuth = false
    var retryPolicy: HRetryPolicy?
    var timeoutInterval: TimeInterval? = 5
    var pingInterval: TimeInterval?
    var maximumMessageSize: Int?
}

/// A request that opts into debug logging.
struct DebugTestSocket: HWebSocketRequestProtocol, HDebugRequestProtocol {
    var url: String
    var headerParameters: [String: String]?
    var needsAuth = false
    var timeoutInterval: TimeInterval? = 5
    let debugType: HDebugRequestType = .requestAndResponse
}

/// A JSON payload used by the encoding tests.
struct ChatEvent: Codable, Equatable, Sendable {
    let type: String
    let text: String
}

/// Connectivity monitor with a fixed answer.
final class FakeConnectivityMonitor: HRequestManagerMonitorProtocol {
    let connected: Bool

    init(connected: Bool) {
        self.connected = connected
    }

    func start() {}

    func isConnectedToNetwork() -> Bool {
        connected
    }
}

/// Auth provider whose header rotates on every `authFailed()`.
actor RotatingAuthProvider: HAuthProviderProtocol {
    private(set) var refreshCount = 0
    private var token: String

    init(token: String = "token-0") {
        self.token = token
    }

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        HAuthorizationHeader(key: "Authorization", value: "Bearer \(token)")
    }

    func authFailed() async {
        refreshCount += 1
        token = "token-\(refreshCount)"
    }
}

/// Auth provider that keeps returning the same header, so a 401 cannot be recovered.
actor StaticAuthProvider: HAuthProviderProtocol {
    private(set) var refreshCount = 0

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        HAuthorizationHeader(key: "X-Api-Key", value: "static")
    }

    func authFailed() async {
        refreshCount += 1
    }
}

enum TestIdentity {
    /// The self-signed test identity shared with the Harbor test suite.
    static func load() async throws -> HMTLSIdentity {
        let p12URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Helpers
            .deletingLastPathComponent()   // HarborWebSocketTests
            .deletingLastPathComponent()   // Tests
            .appendingPathComponent("HarborTests")
            .appendingPathComponent("certificate.p12")
        return try await HMTLS(p12FileUrl: p12URL, passwordProvider: { "notapassword" }).extractIdentity()
    }
}

extension HWebSocketState {
    /// The close code when the state is `.closed`.
    var closeCode: URLSessionWebSocketTask.CloseCode? {
        if case .closed(let code, _) = self { return code }
        return nil
    }

    /// The close reason as text when the state is `.closed`.
    var closeReasonText: String? {
        if case .closed(_, let reason) = self, let reason { return String(decoding: reason, as: UTF8.self) }
        return nil
    }
}

/// Collects the whole `messages` stream.
/// - Returns: The messages received and the error the stream ended with, if any.
func drain(_ socket: HWebSocket) async -> (messages: [HWebSocketMessage], error: HWebSocketError?) {
    var messages: [HWebSocketMessage] = []
    do {
        for try await message in socket.messages {
            messages.append(message)
        }
        return (messages, nil)
    } catch {
        return (messages, error as? HWebSocketError ?? .unknown(error))
    }
}

/// Runs `connect()` and returns the thrown error, failing when it succeeds.
func connectError<Request: HWebSocketRequestProtocol>(_ request: Request, file: StaticString = #filePath, line: UInt = #line) async -> HWebSocketError? {
    do {
        let socket = try await request.connect()
        await socket.close()
        XCTFail("Expected connect() to fail", file: file, line: line)
        return nil
    } catch {
        return error
    }
}

/// Polls `condition` until it holds or the timeout elapses.
func waitUntil(timeout: TimeInterval = 3, _ condition: @escaping @Sendable () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return await condition()
}
