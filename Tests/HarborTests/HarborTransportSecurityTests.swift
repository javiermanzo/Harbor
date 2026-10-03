//
//  HarborTransportSecurityTests.swift
//  HarborTests
//
//  End-to-end tests of Harbor's transport security against a loopback HTTP(S) server:
//  TLS failures surfacing as `.certificate`, custom sessions adopting Harbor's delegate,
//  and credentials stripped from cross-origin redirects. Everything stays on 127.0.0.1.
//

import XCTest
import Security
@testable import Harbor

private struct LoopbackModel: HModel {
    let ok: Bool
}

private struct LoopbackGetRequest: HGetRequestProtocol {
    typealias Model = LoopbackModel
    var url: String
    var headerParameters: [String: String]?
    var needsAuth: Bool = false
    var timeoutInterval: TimeInterval? = 5
    var cacheType: HCache.CacheType? = .disabled
}

/// Auth provider using a custom header key, which URLSession does not strip on redirects by itself.
private struct CustomHeaderAuthProvider: HAuthProviderProtocol {
    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        HAuthorizationHeader(key: "X-Auth-Token", value: "secret-token")
    }

    func authFailed() async {}
}

@HRequestManagerActor
final class HarborTransportSecurityTests: XCTestCase {

    /// A syntactically valid pin (base64 of 32 zero bytes) that matches nothing.
    private let wrongPin = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

    private var servers: [LoopbackHTTPServer] = []

    override func setUp() async throws {
        Harbor.removeAllMocks()
        Harbor.setAuthProvider(nil)
        Harbor.setSSLPinningKeys(nil)
        Harbor.clearMTLS()
        Harbor.setProtocolClasses(nil)
        HConfig.shared.customURLSession = nil
        HRequestManager.connectivityMonitor = FakeConnectivityMonitor(connected: true)
    }

    override func tearDown() async throws {
        servers.forEach { $0.stop() }
        servers.removeAll()
        Harbor.setAuthProvider(nil)
        Harbor.setSSLPinningKeys(nil)
        Harbor.clearMTLS()
        HConfig.shared.customURLSession = nil
        Harbor.setDefaultHeaderParameters(nil)
        HRequestManager.connectivityMonitor = HRequestManagerMonitor()
    }

    // MARK: - TLS Failures (F7)

    func testPinningMismatchOnRealHandshakeFailsWithCertificateError() async throws {
        // Given a TLS server presenting the test certificate and pins that do not match it
        let server = try await startServer(tls: true) { _ in LoopbackHTTPResponse(statusCode: 200, body: Data("{\"ok\":true}".utf8)) }
        Harbor.setSSLPinningKeys([wrongPin])

        // When
        let response = await LoopbackGetRequest(url: "https://127.0.0.1:\(server.port)/pinned").request()

        // Then the rejected handshake is reported as a certificate error, not a cancellation
        XCTAssertEqual(response.failure, .certificate)
        XCTAssertTrue(server.receivedRequests.isEmpty, "No HTTP request may be sent over a rejected connection")
    }

    func testUntrustedCertificateWithoutPinsFailsWithCertificateError() async throws {
        // Given a TLS server with a self-signed certificate and no pinning (default trust evaluation)
        let server = try await startServer(tls: true) { _ in LoopbackHTTPResponse(statusCode: 200, body: Data("{\"ok\":true}".utf8)) }

        // When
        let response = await LoopbackGetRequest(url: "https://127.0.0.1:\(server.port)/untrusted").request()

        // Then the system's TLS URLError maps to .certificate
        XCTAssertEqual(response.failure, .certificate)
    }

    func testCustomSessionWithHarborDelegateEnforcesPinning() async throws {
        // Given pins and a custom session adopting Harbor's delegate after configuring them
        let server = try await startServer(tls: true) { _ in LoopbackHTTPResponse(statusCode: 200, body: Data("{\"ok\":true}".utf8)) }
        Harbor.setSSLPinningKeys([wrongPin])
        let session = URLSession(configuration: .ephemeral, delegate: Harbor.makeURLSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        Harbor.setCustomURLSession(session)

        // When
        let response = await LoopbackGetRequest(url: "https://127.0.0.1:\(server.port)/custom").request()

        // Then pinning applies to the custom session too
        XCTAssertEqual(response.failure, .certificate)
        XCTAssertTrue(server.receivedRequests.isEmpty)
    }

    func testTransportErrorMappingReportsRecordedTrustFailureAsCertificate() async {
        // A rejected challenge surfaces from URLSession as URLError.cancelled
        XCTAssertEqual(HRequestManager.mapTransportError(URLError(.cancelled), trustEvaluationFailed: true), .certificate)
        XCTAssertEqual(HRequestManager.mapTransportError(URLError(.cancelled), trustEvaluationFailed: false), .cancelled)
        XCTAssertEqual(HRequestManager.mapTransportError(URLError(.timedOut), trustEvaluationFailed: false), .timeout)
    }

    func testCertificateURLErrorsMapToCertificate() async {
        let certificateCodes: [URLError.Code] = [
            .serverCertificateHasBadDate,
            .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
            .clientCertificateRejected,
            .clientCertificateRequired
        ]
        for code in certificateCodes {
            XCTAssertEqual(HRequestError.mapURLError(URLError(code)), .certificate, "\(code) should map to .certificate")
        }
    }

    func testGenericTLSFailureMapsToNetworkFailureNotCertificate() async {
        // A dropped handshake or a protocol mismatch is a transient transport error, not a
        // rejected certificate: it must stay retryable and must not be reported as .certificate
        let mapped = HRequestError.mapURLError(URLError(.secureConnectionFailed))
        XCTAssertEqual(mapped, .networkFailure(URLError(.secureConnectionFailed)))
        XCTAssertNotEqual(mapped, .certificate)
        XCTAssertEqual(HRequestManager.mapTransportError(URLError(.secureConnectionFailed), trustEvaluationFailed: false), .networkFailure(URLError(.secureConnectionFailed)))
        // Unless Harbor's own delegate rejected the trust evaluation
        XCTAssertEqual(HRequestManager.mapTransportError(URLError(.secureConnectionFailed), trustEvaluationFailed: true), .certificate)
    }

    // MARK: - Custom Session Warnings (F4)

    func testCustomSessionWithoutHarborDelegateWarnsWhenPinningIsConfigured() async {
        // Given pins configured
        Harbor.setSSLPinningKeys([wrongPin])

        // When a custom session without Harbor's delegate is set
        HConfig.shared.customURLSession = URLSession(configuration: .ephemeral)

        // Then a warning is produced
        let warning = Harbor.warnIfCustomURLSessionBypassesSecurity(afterSecurityChange: false)
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning?.contains("NOT enforced") == true)
    }

    func testPinningConfiguredAfterCustomSessionWarns() async {
        // Given a custom session without Harbor's delegate and no pins: nothing to warn about
        Harbor.setCustomURLSession(URLSession(configuration: .ephemeral))
        XCTAssertNil(Harbor.warnIfCustomURLSessionBypassesSecurity(afterSecurityChange: false))

        // When pins are configured afterwards, the bypass is reported
        Harbor.setSSLPinningKeys([wrongPin])
        XCTAssertNotNil(Harbor.warnIfCustomURLSessionBypassesSecurity(afterSecurityChange: true))
    }

    func testCustomSessionWithHarborDelegateWarnsOnlyWhenConfigurationChanges() async {
        // Given pins and a session built with Harbor's delegate
        Harbor.setSSLPinningKeys([wrongPin])
        let session = URLSession(configuration: .ephemeral, delegate: Harbor.makeURLSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        HConfig.shared.customURLSession = session

        // Then setting it is fine, but a later pin change makes its snapshot stale
        XCTAssertNil(Harbor.warnIfCustomURLSessionBypassesSecurity(afterSecurityChange: false))
        XCTAssertNotNil(Harbor.warnIfCustomURLSessionBypassesSecurity(afterSecurityChange: true))
    }

    func testNoWarningWithoutCustomSession() async {
        Harbor.setSSLPinningKeys([wrongPin])
        XCTAssertNil(Harbor.warnIfCustomURLSessionBypassesSecurity(afterSecurityChange: true))
    }

    // MARK: - Redirects (F5)

    func testCrossOriginRedirectStripsCredentialsOnTheWire() async throws {
        // Given a landing server on another origin and a server redirecting to it
        let landing = try await startServer { _ in LoopbackHTTPResponse(statusCode: 200, body: Data("{\"ok\":true}".utf8)) }
        let landingURL = "http://localhost:\(landing.port)/landing"
        let origin = try await startServer { _ in LoopbackHTTPResponse(statusCode: 302, headers: ["Location": landingURL]) }

        Harbor.setAuthProvider(CustomHeaderAuthProvider())
        let request = LoopbackGetRequest(url: "http://127.0.0.1:\(origin.port)/start",
                                         headerParameters: ["Cookie": "session=abc", "X-API-Key": "key", "Authorization": "Bearer x", "X-Trace": "keep-me"],
                                         needsAuth: true)

        // When
        let response = await request.request()

        // Then the redirect is followed but no credential reaches the other origin
        XCTAssertNil(response.failure)
        XCTAssertEqual(origin.receivedRequests.first?.headers["x-auth-token"], "secret-token")
        let forwarded = try XCTUnwrap(landing.receivedRequests.first)
        XCTAssertNil(forwarded.headers["x-auth-token"])
        XCTAssertNil(forwarded.headers["cookie"])
        XCTAssertNil(forwarded.headers["x-api-key"])
        XCTAssertNil(forwarded.headers["authorization"])
        XCTAssertEqual(forwarded.headers["x-trace"], "keep-me")
    }

    func testSameOriginRedirectKeepsCredentialsOnTheWire() async throws {
        // Given a server redirecting to another path on itself
        let server = try await startServer { request in
            if request.path == "/landing" {
                return LoopbackHTTPResponse(statusCode: 200, body: Data("{\"ok\":true}".utf8))
            }
            return LoopbackHTTPResponse(statusCode: 302, headers: ["Location": "/landing"])
        }
        Harbor.setAuthProvider(CustomHeaderAuthProvider())
        let request = LoopbackGetRequest(url: "http://127.0.0.1:\(server.port)/start", headerParameters: ["Cookie": "session=abc"], needsAuth: true)

        // When
        let response = await request.request()

        // Then
        XCTAssertNil(response.failure)
        let landing = try XCTUnwrap(server.receivedRequests.first { $0.path == "/landing" })
        XCTAssertEqual(landing.headers["x-auth-token"], "secret-token")
        XCTAssertEqual(landing.headers["cookie"], "session=abc")
    }

    // MARK: - Helpers

    private func startServer(tls: Bool = false, handler: @escaping @Sendable (LoopbackHTTPRequest) -> LoopbackHTTPResponse) async throws -> LoopbackHTTPServer {
        let identity = tls ? try await loadTestIdentity().identity : nil
        let server = try LoopbackHTTPServer(identity: identity, handler: handler)
        try await server.start()
        servers.append(server)
        return server
    }

    private func loadTestIdentity() async throws -> HMTLSIdentity {
        let p12URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("certificate.p12")
        return try await HMTLS(p12FileUrl: p12URL, passwordProvider: { "notapassword" }).extractIdentity()
    }
}

private extension HResponseWithResult {
    /// The error carried by the response, or `nil` on success.
    var failure: HRequestError? {
        if case .error(let error) = self { return error }
        return nil
    }
}
