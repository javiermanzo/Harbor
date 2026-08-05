//
//  HURLSessionDelegateTests.swift
//  HarborTests
//
//  Created by Javier Manzo on 06/07/2025.
//

import XCTest
@testable import Harbor

final class HURLSessionDelegateTests: XCTestCase {

    // The pin of Tests/HarborTests/certificate.p12's leaf certificate, matching
    // HarborSecurityTests.testSPKIPinMatchesOpenSSLOutput.
    private let testPin = "X39uJq4Gmf5YvT9e7Q/Cc1DMepSL8aYi7hBI5l6qgO4="
    // A syntactically valid pin (base64 of 32 zero bytes) that matches nothing.
    private let wrongPin = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

    // MARK: - mTLS Challenge Tests

    func testDelegateHandlesMissingIdentity() {
        // Given
        // Initialize delegate with nil identity
        let delegate = HURLSessionDelegate(mTLSIdentity: nil, sslPinningKeys: nil)

        let challenge = makeChallenge(host: "example.com", authenticationMethod: NSURLAuthenticationMethodClientCertificate)

        let expectation = XCTestExpectation(description: "Challenge with nil identity")

        // When
        delegate.urlSession(URLSession.shared, didReceive: challenge) { disposition, credential in
            // Then
            // Should cancel because identity is missing
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            XCTAssertNil(credential)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testMTLSChallengeSendsCertificateChain() throws {
        // Given
        let identity = try loadTestIdentity()
        let expectedChainCount = try XCTUnwrap(identity.certificateChain, "Identity should include the certificate chain").count
        XCTAssertGreaterThan(expectedChainCount, 0)

        let delegate = HURLSessionDelegate(mTLSIdentity: identity, sslPinningKeys: nil)

        let challenge = makeChallenge(host: "example.com", authenticationMethod: NSURLAuthenticationMethodClientCertificate)

        let expectation = XCTestExpectation(description: "Challenge with identity and chain")

        // When
        delegate.urlSession(URLSession.shared, didReceive: challenge) { disposition, credential in
            // Then
            XCTAssertEqual(disposition, .useCredential)
            XCTAssertEqual(credential?.identity, identity.identity)
            XCTAssertEqual(credential?.certificates.count, expectedChainCount)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - SSL Pinning Challenge Tests

    func testSSLPinningWithNilTrustCancels() {
        // Given a delegate with pinning keys and a challenge without a serverTrust object
        let delegate = HURLSessionDelegate(mTLSIdentity: nil, sslPinningKeys: [testPin])
        let challenge = makeChallenge(host: "secure.example.com", authenticationMethod: NSURLAuthenticationMethodServerTrust)

        let expectation = XCTestExpectation(description: "SSL Pinning with nil trust")

        // When
        delegate.urlSession(URLSession.shared, didReceive: challenge) { disposition, _ in
            // Then
            // Should cancel because serverTrust is nil
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testSSLPinningWithMatchingPinUsesCredential() throws {
        // Given a server trust whose leaf certificate matches the configured pin
        let serverTrust = try makeServerTrust()
        let delegate = HURLSessionDelegate(mTLSIdentity: nil, sslPinningKeys: [testPin])

        // When
        let result = delegate.matchPins(serverTrust: serverTrust, sslPinningKeys: [testPin])

        // Then
        XCTAssertEqual(result.disposition, .useCredential)
        XCTAssertNotNil(result.credential)
    }

    func testSSLPinningWithWrongPinCancels() throws {
        // Given a server trust whose certificate does not match the configured pin
        let serverTrust = try makeServerTrust()
        let delegate = HURLSessionDelegate(mTLSIdentity: nil, sslPinningKeys: [wrongPin])

        // When
        let result = delegate.matchPins(serverTrust: serverTrust, sslPinningKeys: [wrongPin])

        // Then
        XCTAssertEqual(result.disposition, .cancelAuthenticationChallenge)
        XCTAssertNil(result.credential)
    }

    func testMatchPinsCancelsForUntrustedChainEvenWithMatchingPin() throws {
        // Given a server trust that does not evaluate as valid and a pin matching its certificate
        let serverTrust = try makeUntrustedServerTrust()
        let delegate = HURLSessionDelegate(mTLSIdentity: nil, sslPinningKeys: [testPin])

        // When
        let result = delegate.matchPins(serverTrust: serverTrust, sslPinningKeys: [testPin])

        // Then pins are never matched against an untrusted chain
        XCTAssertEqual(result.disposition, .cancelAuthenticationChallenge)
        XCTAssertNil(result.credential)
    }

    func testAsyncPinningEvaluationAnswersWithCredentialForValidPin() throws {
        // Given a trusted server trust whose certificate matches the configured pin
        let serverTrust = try makeServerTrust()
        let delegate = HURLSessionDelegate(mTLSIdentity: nil, sslPinningKeys: [testPin])

        let expectation = XCTestExpectation(description: "Async pinning evaluation answers the challenge")

        // When the pinning flow evaluates the trust and answers through the completion handler
        delegate.evaluateAndMatchPins(serverTrust: serverTrust, sslPinningKeys: [testPin]) { disposition, credential in
            // Then the matching pin uses the credential
            XCTAssertEqual(disposition, .useCredential)
            XCTAssertNotNil(credential)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testAsyncPinningEvaluationCancelsForUntrustedChain() throws {
        // Given a server trust that does not evaluate as valid and a pin matching its certificate
        let serverTrust = try makeUntrustedServerTrust()
        let delegate = HURLSessionDelegate(mTLSIdentity: nil, sslPinningKeys: [testPin])

        let expectation = XCTestExpectation(description: "Async pinning evaluation cancels the challenge")

        // When
        delegate.evaluateAndMatchPins(serverTrust: serverTrust, sslPinningKeys: [testPin]) { disposition, credential in
            // Then the challenge is cancelled without matching pins against the untrusted chain
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            XCTAssertNil(credential)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Per-Host SSL Pinning Tests

    func testSSLPinningIsEnforcedForConfiguredHost() throws {
        // Given pins scoped to a specific host and a challenge from that host
        let delegate = HURLSessionDelegate(mTLSIdentity: nil, sslPinningKeys: nil, sslPinningKeysByHost: ["secure.example.com": [testPin]])
        let challenge = makeChallenge(host: "secure.example.com", authenticationMethod: NSURLAuthenticationMethodServerTrust)

        let expectation = XCTestExpectation(description: "Pinning enforced for configured host")

        // When
        delegate.urlSession(URLSession.shared, didReceive: challenge) { disposition, _ in
            // Then pinning applies: without a serverTrust the challenge is cancelled, not passed through
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testSSLPinningPassesThroughForUnconfiguredHost() throws {
        // Given pins scoped to a specific host and a challenge from a different host
        let delegate = HURLSessionDelegate(mTLSIdentity: nil, sslPinningKeys: nil, sslPinningKeysByHost: ["secure.example.com": [testPin]])
        let challenge = makeChallenge(host: "other.example.com", authenticationMethod: NSURLAuthenticationMethodServerTrust)

        let expectation = XCTestExpectation(description: "Default handling for unconfigured host")

        // When
        delegate.urlSession(URLSession.shared, didReceive: challenge) { disposition, credential in
            // Then the host is not pinned and gets default handling
            XCTAssertEqual(disposition, .performDefaultHandling)
            XCTAssertNil(credential)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testSSLPinningGlobalKeysStillApplyToEveryHost() throws {
        // Given global pins and scoped pins, a challenge from an unscoped host uses the global ones
        let delegate = HURLSessionDelegate(mTLSIdentity: nil, sslPinningKeys: [testPin], sslPinningKeysByHost: ["secure.example.com": [testPin]])
        let challenge = makeChallenge(host: "other.example.com", authenticationMethod: NSURLAuthenticationMethodServerTrust)

        let expectation = XCTestExpectation(description: "Global pins apply to unscoped host")

        // When
        delegate.urlSession(URLSession.shared, didReceive: challenge) { disposition, _ in
            // Then the global pins apply, so the missing serverTrust cancels the challenge
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Host Normalization Tests

    func testNormalizedHostLowercasesAndStripsTrailingRootDot() {
        XCTAssertEqual(HURLSessionDelegate.normalizedHost("API.Example.COM"), "api.example.com")
        XCTAssertEqual(HURLSessionDelegate.normalizedHost("api.example.com."), "api.example.com")
        XCTAssertEqual(HURLSessionDelegate.normalizedHost("api.example.com"), "api.example.com")
    }

    func testSSLPinningIsEnforcedForHostWithDifferentCase() throws {
        // Given pins stored for a lowercase host and a challenge using a different case;
        // DNS names are case-insensitive, so pinning must still apply
        let delegate = HURLSessionDelegate(mTLSIdentity: nil, sslPinningKeys: nil, sslPinningKeysByHost: ["secure.example.com": [testPin]])
        let challenge = makeChallenge(host: "SECURE.Example.COM", authenticationMethod: NSURLAuthenticationMethodServerTrust)

        let expectation = XCTestExpectation(description: "Pinning enforced for differently-cased host")

        // When
        delegate.urlSession(URLSession.shared, didReceive: challenge) { disposition, _ in
            // Then pinning applies: without a serverTrust the challenge is cancelled, not passed through
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testSSLPinningIsEnforcedForHostWithTrailingRootDot() throws {
        // Given pins stored for a host without a root-label dot and a challenge carrying it
        let delegate = HURLSessionDelegate(mTLSIdentity: nil, sslPinningKeys: nil, sslPinningKeysByHost: ["secure.example.com": [testPin]])
        let challenge = makeChallenge(host: "secure.example.com.", authenticationMethod: NSURLAuthenticationMethodServerTrust)

        let expectation = XCTestExpectation(description: "Pinning enforced for host with trailing dot")

        // When
        delegate.urlSession(URLSession.shared, didReceive: challenge) { disposition, _ in
            // Then pinning applies: without a serverTrust the challenge is cancelled, not passed through
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    @HRequestManagerActor
    func testSetSSLPinningKeysForHostsStoresNormalizedKeys() async {
        // Given pins registered for a mixed-case host with a trailing root-label dot
        Harbor.setSSLPinningKeys([testPin], forHosts: ["STORED.Example.COM."])

        // Then the stored key is normalized
        let stored = HConfig.shared.sslPinningKeysByHost
        XCTAssertEqual(stored?["stored.example.com"], [testPin])
        XCTAssertNil(stored?["STORED.Example.COM."])

        // Cleanup with a differently-cased spelling also removes the entry
        Harbor.setSSLPinningKeys(nil, forHosts: ["stored.example.com."])
        let afterRemoval = HConfig.shared.sslPinningKeysByHost
        XCTAssertNil(afterRemoval?["stored.example.com"])
    }

    @HRequestManagerActor
    func testSetSSLPinningKeysForHostsSkipsEmptyKeys() async {
        // Given an empty host key
        Harbor.setSSLPinningKeys([testPin], forHosts: ["   "])

        // Then nothing is stored for it
        let stored = HConfig.shared.sslPinningKeysByHost
        XCTAssertTrue(stored?.isEmpty ?? true)

        // Cleanup
        Harbor.setSSLPinningKeys(nil, forHosts: ["   "])
    }

    // MARK: - Helpers

    private func makeChallenge(host: String, authenticationMethod: String) -> URLAuthenticationChallenge {
        let protectionSpace = URLProtectionSpace(host: host,
                                                 port: 443,
                                                 protocol: "https",
                                                 realm: nil,
                                                 authenticationMethod: authenticationMethod)
        return URLAuthenticationChallenge(protectionSpace: protectionSpace,
                                          proposedCredential: nil,
                                          previousFailureCount: 0,
                                          failureResponse: nil,
                                          error: nil,
                                          sender: MockURLSessionSender())
    }

    private func loadTestIdentity() throws -> HMTLSIdentity {
        let p12URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("certificate.p12")
        let mTLS = HMTLS(p12FileUrl: p12URL, passwordProvider: { "notapassword" })
        return try mTLS.extractIdentity()
    }

    /// Builds a synthetic SecTrust from the test certificate with the certificate installed
    /// as an anchor, so trust evaluation succeeds for the self-signed certificate.
    private func makeServerTrust() throws -> SecTrust {
        let serverTrust = try makeUntrustedServerTrust()
        let identity = try loadTestIdentity()
        let certificate = try XCTUnwrap(identity.certificateChain?.first)
        SecTrustSetAnchorCertificates(serverTrust, [certificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, false)
        return serverTrust
    }

    /// Builds a synthetic SecTrust from the test certificate. The trust is not anchored,
    /// so evaluating it fails on the self-signed certificate.
    private func makeUntrustedServerTrust() throws -> SecTrust {
        let identity = try loadTestIdentity()
        let certificate = try XCTUnwrap(identity.certificateChain?.first)
        var serverTrust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &serverTrust)
        guard status == errSecSuccess, let serverTrust else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return serverTrust
    }
}

// Mock sender to satisfy URLAuthenticationChallenge
final class MockURLSessionSender: NSObject, URLAuthenticationChallengeSender, @unchecked Sendable {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}
