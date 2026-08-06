//
//  HarborSecurityTests.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import XCTest
import Security
@testable import Harbor

@HRequestManagerActor
final class HarborSecurityTests: XCTestCase {

    let testPassword = "notapassword"

    var testP12URL: URL? {
        let thisFileURL = URL(fileURLWithPath: #filePath)
        // Tests/HarborTests/HarborSecurityTests.swift -> Tests/HarborTests/certificate.p12
        let harborTestsDir = thisFileURL.deletingLastPathComponent()
        let candidate = harborTestsDir.appendingPathComponent("certificate.p12")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    override func setUp() async throws {
        Harbor.removeAllMocks()
        // Reset security configurations
        Harbor.setSSLPinningKeys(nil)
        Harbor.clearMTLS()
    }
    
    override func tearDown() async throws {
        Harbor.removeAllMocks()
        // Reset security configurations
        Harbor.setSSLPinningKeys(nil)
        Harbor.clearMTLS()
    }
    
    // MARK: - SSL Pinning Tests
    
    func testSSLPinningConfiguration() async throws {
        // Given
        let testSHA256 = "ABC123456789ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF"
        
        // When
        Harbor.setSSLPinningKeys([testSHA256])
        
        // Then
        let keys = await HConfig.shared.sslPinningKeys
        XCTAssertEqual(keys, [testSHA256])
    }
    
    func testSSLPinningWithNilValue() async throws {
        // Given
        let testSHA256 = "ABC123456789ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF"
        Harbor.setSSLPinningKeys([testSHA256])
        
        // When
        Harbor.setSSLPinningKeys(nil)
        
        // Then
        let keys = await HConfig.shared.sslPinningKeys
        XCTAssertNil(keys)
    }
    
    func testSSLPinningWithValidRequest() async throws {
        // Given
        let testSHA256 = "ABC123456789ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF"
        Harbor.setSSLPinningKeys([testSHA256])
        
        let mockResponse = TestSecureData(secret: "pinned-data")
        let jsonData = try JSONEncoder().encode(mockResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = HMock(request: SecureGetRequest.self, statusCode: 200, jsonResponse: jsonString)
        Harbor.register(mock: mock)
        
        // When
        let request = SecureGetRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success(let data):
            XCTAssertEqual(data.secret, "pinned-data")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    // MARK: - mTLS Tests
    
    func testMTLSConfiguration() async throws {
        // Given
        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")

        let mTLS = makeMTLS(url: unwrappedP12URL, password: testPassword)

        // When
        try await Harbor.setMTLS(mTLS)
        
        // Then
        let identity = HConfig.shared.mTLSIdentity
        XCTAssertNotNil(identity)
    }
    
    func testMTLSWithNilValue() async throws {
        // Given
        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")

        let mTLS = makeMTLS(url: unwrappedP12URL, password: testPassword)
        try await Harbor.setMTLS(mTLS)
        
        // When
        Harbor.clearMTLS()
        
        // Then
        // mTLS should be disabled
        let identity = HConfig.shared.mTLSIdentity
        XCTAssertNil(identity)
    }

    // MARK: - mTLS Error Tests

    func testMTLSExtractIdentityWithNonexistentFileThrowsFileNotFound() async throws {
        // Given
        let mTLS = makeMTLS(url: URL(fileURLWithPath: "/tmp/harbor-definitely-missing.p12"), password: testPassword)

        // When / Then
        do {
            _ = try await mTLS.extractIdentity()
            XCTFail("Expected extractIdentity to throw")
        } catch {
            XCTAssertEqual(error as? HMTLSError, .fileNotFound)
        }
    }

    func testMTLSExtractIdentityWithWrongPasswordThrowsInvalidPassword() async throws {
        // Given
        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")
        let mTLS = makeMTLS(url: unwrappedP12URL, password: "wrong-password")

        // When / Then
        do {
            _ = try await mTLS.extractIdentity()
            XCTFail("Expected extractIdentity to throw")
        } catch {
            XCTAssertEqual(error as? HMTLSError, .invalidPassword)
        }
    }

    func testMTLSExtractIdentityWithThrowingPasswordProviderThrowsPasswordProviderFailed() async throws {
        // Given a provider that fails to supply the password
        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")
        let mTLS = HMTLS(p12FileUrl: unwrappedP12URL) { throw URLError(.cannotLoadFromNetwork) }

        // When / Then
        do {
            _ = try await mTLS.extractIdentity()
            XCTFail("Expected extractIdentity to throw")
        } catch {
            XCTAssertEqual(error as? HMTLSError, .passwordProviderFailed)
        }
    }

    func testSetMTLSThrowsAndLeavesIdentityUnsetOnFailure() async throws {
        // Given
        let mTLS = makeMTLS(url: URL(fileURLWithPath: "/tmp/harbor-definitely-missing.p12"), password: testPassword)

        // Then
        do {
            try await Harbor.setMTLS(mTLS)
            XCTFail("Expected setMTLS to throw")
        } catch {
            XCTAssertEqual(error as? HMTLSError, .fileNotFound)
        }
        XCTAssertNil(HConfig.shared.mTLSIdentity)
    }

    func testSetMTLSSucceedsAndConfiguresIdentity() async throws {
        // Given
        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")
        let mTLS = makeMTLS(url: unwrappedP12URL, password: testPassword)

        // Then
        try await Harbor.setMTLS(mTLS)
        XCTAssertNotNil(HConfig.shared.mTLSIdentity)
    }
    
    // MARK: - Combined Security Tests
    
    func testCombinedSSLPinningAndMTLS() async throws {
        // Given
        let testSHA256 = "ABC123456789ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF"
        Harbor.setSSLPinningKeys([testSHA256])

        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")
        let mTLS = makeMTLS(url: unwrappedP12URL, password: testPassword)
        try await Harbor.setMTLS(mTLS)
        
        let mockResponse = TestSecureData(secret: "fully-secured-data")
        let jsonData = try JSONEncoder().encode(mockResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = HMock(request: FullySecureGetRequest.self, statusCode: 200, jsonResponse: jsonString)
        Harbor.register(mock: mock)
        
        // When
        let request = FullySecureGetRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success(let data):
            XCTAssertEqual(data.secret, "fully-secured-data")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    // MARK: - Security Error Tests
    
    func testSSLPinningFailure() async throws {
        // Given
        let testSHA256 = "INVALID_HASH"
        Harbor.setSSLPinningKeys([testSHA256])
        
        // Mock a SSL-related failure (using existing error types)
        let mock = HMock(request: SecureGetRequest.self, statusCode: 500, error: .noConnection)
        Harbor.register(mock: mock)
        
        // When
        let request = SecureGetRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTFail("Expected SSL-related failure")
        case .error(let error):
            switch error {
            case .noConnection:
                let count = await HMocker.callCount(for: SecureGetRequest.self)
                XCTAssertEqual(count, 1)
            default:
                XCTFail("Expected connection error but got: \(error)")
            }
        }
    }
    
    func testMTLSCertificateError() async throws {
        // Given
        let testP12URL = URL(fileURLWithPath: "/tmp/invalid.p12")
        let testPassword = "wrong-password"
        let mTLS = makeMTLS(url: testP12URL, password: testPassword)
        try? await Harbor.setMTLS(mTLS)
        
        // Mock a certificate-related error (using existing error types)
        let mock = HMock(request: MTLSGetRequest.self, statusCode: 403)
        Harbor.register(mock: mock)
        
        // When
        let request = MTLSGetRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTFail("Expected certificate-related error")
        case .error(let error):
            switch error {
            case .api(statusCode: let code, data: _):
                XCTAssertEqual(code, 403) // Expected 403 Forbidden (certificate issue)
            default:
                XCTFail("Expected API error with 403 status but got: \(error)")
            }
        }
    }

    // MARK: - SPKI Pinning Tests

    func testSPKIPinMatchesOpenSSLOutput() async throws {
        // Given
        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")
        let mTLS = makeMTLS(url: unwrappedP12URL, password: testPassword)
        let identity = try await mTLS.extractIdentity()
        let certificate = try XCTUnwrap(identity.certificateChain?.first)

        // When
        let pin = Harbor.computePin(for: certificate)

        // Then
        // Expected value generated from Tests/HarborTests/certificate.p12 with:
        // openssl pkcs12 -in certificate.p12 -nokeys -passin pass:notapassword | \
        //   openssl x509 -pubkey -noout | \
        //   openssl pkey -pubin -outform der | \
        //   openssl dgst -sha256 -binary | \
        //   openssl base64
        XCTAssertEqual(pin, "X39uJq4Gmf5YvT9e7Q/Cc1DMepSL8aYi7hBI5l6qgO4=")
    }

    func testSPKIPinMatchesOpenSSLOutputEC256() async throws {
        // Given
        let certificate = try loadDERCertificate(named: "certificate-ec256.der")

        // When
        let pin = Harbor.computePin(for: certificate)

        // Then
        // Expected value generated from Tests/HarborTests/certificate-ec256.der with:
        // openssl x509 -inform DER -in certificate-ec256.der -pubkey -noout | \
        //   openssl pkey -pubin -outform der | \
        //   openssl dgst -sha256 -binary | \
        //   openssl base64
        XCTAssertEqual(pin, "w2fnV22DZKdxvDvT5Oj7K3LHDl0E2gRrIIhHK2L0F/E=")
    }

    func testSPKIPinMatchesOpenSSLOutputRSA4096() async throws {
        // Given
        let certificate = try loadDERCertificate(named: "certificate-rsa4096.der")

        // When
        let pin = Harbor.computePin(for: certificate)

        // Then
        // Expected value generated from Tests/HarborTests/certificate-rsa4096.der with:
        // openssl x509 -inform DER -in certificate-rsa4096.der -pubkey -noout | \
        //   openssl pkey -pubin -outform der | \
        //   openssl dgst -sha256 -binary | \
        //   openssl base64
        XCTAssertEqual(pin, "8tTpKUiR9q0MRHDOcFD1qGCUeliu9b+wQeGMT16qm7Y=")
    }

    private func loadDERCertificate(named fileName: String) throws -> SecCertificate {
        let thisFileURL = URL(fileURLWithPath: #filePath)
        let certURL = thisFileURL.deletingLastPathComponent().appendingPathComponent(fileName)
        let certData = try Data(contentsOf: certURL)
        return try XCTUnwrap(SecCertificateCreateWithData(nil, certData as CFData), "\(fileName) is not a valid DER certificate")
    }

    func testSPKIPinDiffersFromLegacyRawKeyHash() async throws {
        // Given
        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")
        let mTLS = makeMTLS(url: unwrappedP12URL, password: testPassword)
        let identity = try await mTLS.extractIdentity()
        let certificate = try XCTUnwrap(identity.certificateChain?.first)

        // When
        let pin = try XCTUnwrap(Harbor.computePin(for: certificate))
        let publicKey = try XCTUnwrap(SecCertificateCopyKey(certificate))
        let rawKeyData = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
        let legacyRawKeyHash = SHA256.sha256Base64(data: rawKeyData)

        // Then
        // The SPKI pin must not match the legacy format (SHA-256 of the raw public key bytes)
        XCTAssertNotEqual(pin, legacyRawKeyHash)
    }

    // MARK: - Pin Validation Tests

    func testIsValidPin() async {
        // 44 chars with padding
        XCTAssertTrue(HSPKI.isValidPin("X39uJq4Gmf5YvT9e7Q/Cc1DMepSL8aYi7hBI5l6qgO4="))
        // 43 chars without padding
        XCTAssertTrue(HSPKI.isValidPin("X39uJq4Gmf5YvT9e7Q/Cc1DMepSL8aYi7hBI5l6qgO4"))
        // Not base64
        XCTAssertFalse(HSPKI.isValidPin("INVALID_HASH"))
        // Hex-encoded SHA-256 (decodes to more than 32 bytes as base64)
        XCTAssertFalse(HSPKI.isValidPin("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))
        // Empty
        XCTAssertFalse(HSPKI.isValidPin(""))
        // Valid base64 but wrong length (16 bytes)
        XCTAssertFalse(HSPKI.isValidPin("AQIDBAUGBwgJCgsMDQ4PEA=="))
    }

    func testSetSSLPinningKeysWithMalformedPinDoesNotCrash() async {
        // Given / When: malformed pins should only log a warning, not crash
        Harbor.setSSLPinningKeys(["INVALID_HASH", "X39uJq4Gmf5YvT9e7Q/Cc1DMepSL8aYi7hBI5l6qgO4="])

        // Then
        XCTAssertEqual(HConfig.shared.sslPinningKeys?.count, 2)
    }

    func testNormalizePin() async {
        // Padding must not affect matching: 44-char and 43-char forms normalize equal
        XCTAssertEqual(HSPKI.normalizePin("X39uJq4Gmf5YvT9e7Q/Cc1DMepSL8aYi7hBI5l6qgO4="),
                       HSPKI.normalizePin("X39uJq4Gmf5YvT9e7Q/Cc1DMepSL8aYi7hBI5l6qgO4"))
    }

    // MARK: - PKCS12 Certificate Chain Tests

    func testPKCS12ExtractsCertificateChain() async throws {
        // Given
        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")
        let p12Data = try Data(contentsOf: unwrappedP12URL)

        // When
        let pkcs12 = try PKCS12.parse(p12Data: p12Data, password: testPassword)

        // Then
        XCTAssertNotNil(pkcs12.identity)
        let certChain = try XCTUnwrap(pkcs12.certChain, "certChain should be extracted as [SecCertificate]")
        XCTAssertFalse(certChain.isEmpty)
    }

    // MARK: - PKCS12 Failure Tests

    func testPKCS12ParseWithWrongPasswordThrowsImportFailed() async throws {
        // Given
        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")
        let p12Data = try Data(contentsOf: unwrappedP12URL)

        // When / Then
        XCTAssertThrowsError(try PKCS12.parse(p12Data: p12Data, password: "wrong-password")) { error in
            guard let pkcs12Error = error as? PKCS12Error, case .importFailed(let status) = pkcs12Error else {
                XCTFail("Expected PKCS12Error.importFailed but got: \(error)")
                return
            }
            XCTAssertEqual(status, errSecAuthFailed)
        }
    }

    func testPKCS12ParseWithCorruptDataThrows() async throws {
        // Given
        let corruptData = Data("not a p12 archive".utf8)

        // When / Then
        XCTAssertThrowsError(try PKCS12.parse(p12Data: corruptData, password: testPassword)) { error in
            guard let pkcs12Error = error as? PKCS12Error, case .importFailed = pkcs12Error else {
                XCTFail("Expected PKCS12Error.importFailed but got: \(error)")
                return
            }
        }
    }

    // MARK: - HMTLS Password Handling Tests

    func testMTLSDescriptionRedactsPassword() async throws {
        // Given
        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")
        let mTLS = makeMTLS(url: unwrappedP12URL, password: testPassword)

        // When
        let description = String(describing: mTLS)
        let interpolated = "\(mTLS)"

        // Then
        XCTAssertFalse(description.contains(testPassword))
        XCTAssertFalse(interpolated.contains(testPassword))
        XCTAssertTrue(description.contains("<redacted>"))
        XCTAssertTrue(description.contains("certificate.p12"))
    }

    func testMTLSPasswordProviderIsCalledOncePerExtraction() async throws {
        // Given
        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")
        let callCount = SendableCounter()
        let mTLS = HMTLS(p12FileUrl: unwrappedP12URL) {
            callCount.increment()
            return "notapassword"
        }

        // When
        _ = try await mTLS.extractIdentity()

        // Then
        XCTAssertEqual(callCount.value, 1)
    }

    func testMTLSIdentityIncludesCertificateChain() async throws {
        // Given
        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")
        let mTLS = makeMTLS(url: unwrappedP12URL, password: testPassword)

        // When
        let identity = try await mTLS.extractIdentity()

        // Then
        let certChain = try XCTUnwrap(identity.certificateChain)
        XCTAssertFalse(certChain.isEmpty)
    }
}

// MARK: - Test Helpers

/// Builds an mTLS configuration with a fixed password exposed through the provider closure.
private func makeMTLS(url: URL, password: String) -> HMTLS {
    HMTLS(p12FileUrl: url, passwordProvider: { password })
}

/// A lock-protected counter that can be shared with a `@Sendable` closure.
private final class SendableCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock()
        _value += 1
        lock.unlock()
    }
}

// MARK: - Test Models

private struct TestSecureData: HModel {
    let secret: String
}

// MARK: - Test Request Implementations

private struct SecureGetRequest: HGetRequestProtocol {
    typealias Model = TestSecureData
    
    var url: String { "https://secure.example.com/data" }
}

private struct MTLSGetRequest: HGetRequestProtocol {
    typealias Model = TestSecureData
    
    var url: String { "https://mtls.example.com/data" }
}

private struct FullySecureGetRequest: HGetRequestProtocol {
    typealias Model = TestSecureData
    
    var url: String { "https://fullysecure.example.com/data" }
}

