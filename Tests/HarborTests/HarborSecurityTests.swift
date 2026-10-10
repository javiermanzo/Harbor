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

    // A pinning mismatch on a real TLS handshake is covered end to end in
    // HarborTransportSecurityTests.testPinningMismatchOnRealHandshakeFailsWithCertificateError.

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

    func testSPKIPinMatchesOpenSSLOutputRSA3072() async throws {
        // Given
        let certificate = try certificate(base64DER: Self.rsa3072CertificateBase64)

        // When
        let pin = Harbor.computePin(for: certificate)

        // Then
        // Expected value generated from rsa3072CertificateBase64 (decoded to cert.der) with:
        // openssl x509 -inform DER -in cert.der -pubkey -noout | \
        //   openssl pkey -pubin -outform der | \
        //   openssl dgst -sha256 -binary | \
        //   openssl base64
        XCTAssertEqual(pin, "v9sPP7iIhW4zD3eVto3QPDT/ux7FWwLvS1r56FJSWrs=")
    }

    func testSPKIPinMatchesOpenSSLOutputEC521() async throws {
        // Given
        let certificate = try certificate(base64DER: Self.ec521CertificateBase64)

        // When
        let pin = Harbor.computePin(for: certificate)

        // Then
        // Expected value generated from ec521CertificateBase64 with the same openssl pipeline.
        XCTAssertEqual(pin, "pN/3OV3mMK7uoHEet/QzKZgDMnMuvPiPvTQpNdUrqnQ=")
    }

    func testSPKIDataForGeneratedKeysStartsWithTheExpectedDERHeader() async throws {
        // Expected SubjectPublicKeyInfo prefixes (outer SEQUENCE, AlgorithmIdentifier and the
        // BIT STRING header) for each supported key type/size (RSA-4096 is covered by its
        // certificate vector, generating one is slow). The RSA-2048 and P-256/384 values are
        // TrustKit's fixed headers; the RSA-3072 and P-521 ones were read from
        // `openssl pkey -pubin -outform der` for keys of those types.
        let cases: [(keyType: CFString, bits: Int, header: String)] = [
            (kSecAttrKeyTypeRSA, 2048, "30820122300d06092a864886f70d01010105000382010f00"),
            (kSecAttrKeyTypeRSA, 3072, "308201a2300d06092a864886f70d01010105000382018f00"),
            (kSecAttrKeyTypeECSECPrimeRandom, 256, "3059301306072a8648ce3d020106082a8648ce3d030107034200"),
            (kSecAttrKeyTypeECSECPrimeRandom, 384, "3076301006072a8648ce3d020106052b81040022036200"),
            (kSecAttrKeyTypeECSECPrimeRandom, 521, "30819b301006072a8648ce3d020106052b8104002303818600")
        ]

        for testCase in cases {
            // Given a freshly generated key
            let attributes: [String: Any] = [
                kSecAttrKeyType as String: testCase.keyType,
                kSecAttrKeySizeInBits as String: testCase.bits
            ]
            var error: Unmanaged<CFError>?
            let privateKey = try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, &error), "Key generation failed for \(testCase.bits) bits")
            let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
            let rawKey = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)

            // When
            let spki = try XCTUnwrap(HSPKI.spkiData(for: publicKey), "Unsupported key: \(testCase.bits) bits")

            // Then the SPKI is the expected header followed by the raw key
            let hex = spki.map { String(format: "%02x", $0) }.joined()
            XCTAssertTrue(hex.hasPrefix(testCase.header), "Unexpected SPKI header for \(testCase.keyType) \(testCase.bits): \(hex.prefix(60))")
            XCTAssertEqual(spki.suffix(rawKey.count), rawKey)
        }
    }

    func testDERLengthEncoding() async {
        XCTAssertEqual(HSPKI.derLength(0x7f), [0x7f])
        XCTAssertEqual(HSPKI.derLength(0x80), [0x81, 0x80])
        XCTAssertEqual(HSPKI.derLength(0x9b), [0x81, 0x9b])
        XCTAssertEqual(HSPKI.derLength(0x01a2), [0x82, 0x01, 0xa2])
    }

    private func certificate(base64DER: String) throws -> SecCertificate {
        let data = try XCTUnwrap(Data(base64Encoded: base64DER, options: .ignoreUnknownCharacters))
        return try XCTUnwrap(SecCertificateCreateWithData(nil, data as CFData), "Not a valid DER certificate")
    }

    /// Self-signed RSA-3072 certificate (CN=harbor-rsa3072), DER, base64. Generated with
    /// `openssl req -x509 -newkey rsa:3072 -nodes -subj "/CN=harbor-rsa3072" -days 3650 -outform DER`.
    private static let rsa3072CertificateBase64 = """
MIIEEzCCAnugAwIBAgIUR6vGwjdR8V67+Qba2wgMQ7ej0B8wDQYJKoZIhvcNAQELBQAwGTEXMBUG
A1UEAwwOaGFyYm9yLXJzYTMwNzIwHhcNMjYxMDAyMjI0NzQ2WhcNMzYwOTI5MjI0NzQ2WjAZMRcw
FQYDVQQDDA5oYXJib3ItcnNhMzA3MjCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBAKdm
fJfBVR4xX7Oin9/E2w+50DIJqeoT5oGm7BEp3TQCLts6blluAgwE3dpqdUcI00Onkev+pyL+kG1q
zjfVI8hnpmXm/zW8H4Q7Wc+m6qo7sOG+vavgUVLHServqrz2sR40uxBgo6nqU9jIzybyzvBK/08u
esUwuXm2jlISCKEmtcT0l2QZbZtflo3QHelOLpASnLGYn6cULwuQq4gA2oJZnuNW84o2eziZm61g
SthLqx1bqdaZDHWoRCXGY2PYRY3KjUSNqi3y46uuxfD24NMk74WCZKqNHzrtEjgwaxlZ6OMOF4NA
sT05rIqFSpaFyYqCYI40KDdSSm40SdvL+/SlZAli0ZnhqIVksiCo0Xic/PZuo5nDxs3+7vyAWbdY
ed9UKsUAxqjhAEEbVzoHGtCahCyNAlQpFybf+3oQALt347ZzUTQfxm2KD9y+n8aJRFhjdggkixPD
InqAQCxgdJnD+BFnqHLIODFu6tsxhbRu4HW/Qjqw/Tv13cm5/HKy8QIDAQABo1MwUTAdBgNVHQ4E
FgQU8czp6qN7ZndwPsCY902fZ3X/irwwHwYDVR0jBBgwFoAU8czp6qN7ZndwPsCY902fZ3X/irww
DwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAYEAbtCSEJ0lANBzvq3DL4GijewEs8mg
dGVzmdCn/tHZcjqQyRN0To9cxlj/6nv5+YI3eZqPrvo3pepnO7dfM2qoCD6butwfQfhSg9EPXpDI
D7BFBNKeq/zxRm9jVfP4fBJ4SH0wvAqgpVn79SELF8wT2fbaHxGvf+EvY3r17EYPyLRkE1Rci2YK
TrG/Gs0kU17YXPyZZJ/AZX0zM/OdFvw9uJ4MIEdTwJjOeygBA4VCL1zXeb30Pspw0mu8NwGIdM42
3ZkVQEh0VBAAbN+0OEkZpAKiLHraSk7Ertl1kAoNRMMqAUnfC3sZQO108Tvza6bQK+M/DEuHHbg1
xUSHE0ehyyHAO7piNDYmHGJK/ASxS33GoDEJIZkf3KE5TZfMQi/iTs0ScITwwgjl0NDPdNstTLZX
rBXtogww1x0o6h1/NfPIhPQ0aUKStlWWN/qvv/eyS+wD1poHC3/taDtI5b7QcA2xkB3dNPNMUcme
hzqyPAcfIakBtXPfqEmnLMgtSgQ2
"""

    /// Self-signed EC P-521 certificate (CN=harbor-ec521), DER, base64. Generated with
    /// `openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:secp521r1 -nodes -subj "/CN=harbor-ec521" -days 3650 -outform DER`.
    private static let ec521CertificateBase64 = """
MIICCzCCAWygAwIBAgIUa6EicETu5OMu3XWzt1TwiNw2BcswCgYIKoZIzj0EAwIwFzEVMBMGA1UE
AwwMaGFyYm9yLWVjNTIxMB4XDTI2MTAwMjIyNDc0NloXDTM2MDkyOTIyNDc0NlowFzEVMBMGA1UE
AwwMaGFyYm9yLWVjNTIxMIGbMBAGByqGSM49AgEGBSuBBAAjA4GGAAQBQP6xUhXABBB7im/TCxLi
NDIZ/qOJfDkn9n5z8LnIV47la17hIWUk6LZshvxTY3Lq1NtBVPVGjYpHfdoJASKI/yUAA/NUerNE
uZJUqLS52ZKAOXzHcTBmY6zeC6jv0zQaFLwyqg2wUzqd41s/+tch3c65yar6VAc5uZM0Zl68X139
MiGjUzBRMB0GA1UdDgQWBBTx5P4bQgukbOCUuds0F8zIP8vNujAfBgNVHSMEGDAWgBTx5P4bQguk
bOCUuds0F8zIP8vNujAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA4GMADCBiAJCAQzrqVhw
iBWe+vvTJR2x7CFTuUO0hAI+K01O4FslAK6zZCR268ZrYD9IR9vQEd+3ozImnXtNTcgYFm9wQr3T
ikxaAkIAtWcWL/2FEgZotQFd0yMKuhGvRaJXRKS7BggZHVEYwLsPJaV+hdsrOksgLjWe195D8Swh
Q5yH6LFbqNgsTiFSiDM=
"""

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

    // MARK: - mTLS Host Scoping Tests

    func testMTLSHostsAreNormalizedIntoTheExtractedIdentity() async throws {
        // Given an mTLS configuration scoped to hosts spelled in mixed case / with a root dot
        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")
        let mTLS = HMTLS(p12FileUrl: unwrappedP12URL, hosts: ["API.Example.com.", "mtls.example.com"]) { "notapassword" }

        // When
        let identity = try await mTLS.extractIdentity()

        // Then the identity carries the normalized scope and applies only to those hosts
        XCTAssertEqual(identity.hosts, ["api.example.com", "mtls.example.com"])
        XCTAssertTrue(identity.applies(toHost: "api.example.com"))
        XCTAssertTrue(identity.applies(toHost: "MTLS.example.com"))
        XCTAssertFalse(identity.applies(toHost: "evil.example.com"))
        XCTAssertTrue(String(describing: mTLS).contains("api.example.com"))
    }

    func testMTLSWithoutHostsAppliesToEveryHost() async throws {
        // Given the source-compatible initializer (no host scope)
        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")
        let identity = try await makeMTLS(url: unwrappedP12URL, password: testPassword).extractIdentity()

        // Then
        XCTAssertNil(identity.hosts)
        XCTAssertTrue(identity.applies(toHost: "any.example.com"))
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

// MARK: - Test Request Implementations

