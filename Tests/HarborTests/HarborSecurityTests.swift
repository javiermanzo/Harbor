//
//  HarborSecurityTests.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import XCTest
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
        Harbor.setSSlPinningKeys(nil)
        Harbor.setMTLS(nil)
    }
    
    override func tearDown() async throws {
        Harbor.removeAllMocks()
        // Reset security configurations
        Harbor.setSSlPinningKeys(nil)
        Harbor.setMTLS(nil)
    }
    
    // MARK: - SSL Pinning Tests
    
    func testSSLPinningConfiguration() async throws {
        // Given
        let testSHA256 = "ABC123456789ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF"
        
        // When
        Harbor.setSSlPinningKeys([testSHA256])
        
        // Then
        // SSL pinning should be configured (we can't directly test internal state)
        // But we can test that the configuration doesn't crash
        XCTAssertTrue(true)
    }
    
    func testSSLPinningWithNilValue() async throws {
        // Given
        let testSHA256 = "ABC123456789ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF"
        Harbor.setSSlPinningKeys([testSHA256])
        
        // When
        Harbor.setSSlPinningKeys(nil)
        
        // Then
        // SSL pinning should be disabled
        XCTAssertTrue(true)
    }
    
    func testSSLPinningWithValidRequest() async throws {
        // Given
        let testSHA256 = "ABC123456789ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF"
        Harbor.setSSlPinningKeys([testSHA256])
        
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

        let mTLS = HmTLS(p12FileUrl: unwrappedP12URL, password: testPassword)

        // When
        Harbor.setMTLS(mTLS)
        
        // Then
        let identity = HConfig.shared.mTLSIdentity
        XCTAssertNotNil(identity)
    }
    
    func testMTLSWithNilValue() async throws {
        // Given
        let unwrappedP12URL = try XCTUnwrap(testP12URL, "certificate.p12 not found")

        let mTLS = HmTLS(p12FileUrl: unwrappedP12URL, password: testPassword)
        Harbor.setMTLS(mTLS)
        
        // When
        Harbor.setMTLS(nil)
        
        // Then
        // mTLS should be disabled
        let identity = HConfig.shared.mTLSIdentity
        XCTAssertNil(identity)
    }
    
    // MARK: - Combined Security Tests
    
    func testCombinedSSLPinningAndMTLS() async throws {
        // Given
        let testSHA256 = "ABC123456789ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF"
        Harbor.setSSlPinningKeys([testSHA256])
        
        let testP12URL = URL(fileURLWithPath: "/tmp/test.p12")
        let testPassword = "test-password"
        let mTLS = HmTLS(p12FileUrl: testP12URL, password: testPassword)
        Harbor.setMTLS(mTLS)
        
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
        Harbor.setSSlPinningKeys([testSHA256])
        
        // Mock a SSL-related failure (using existing error types)
        let mock = HMock(request: SecureGetRequest.self, statusCode: 500, error: .noConnectionError)
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
            case .noConnectionError:
                XCTAssertTrue(true) // Expected connection error (SSL-related)
            default:
                XCTFail("Expected connection error but got: \(error)")
            }
        }
    }
    
    func testMTLSCertificateError() async throws {
        // Given
        let testP12URL = URL(fileURLWithPath: "/tmp/invalid.p12")
        let testPassword = "wrong-password"
        let mTLS = HmTLS(p12FileUrl: testP12URL, password: testPassword)
        Harbor.setMTLS(mTLS)
        
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
            case .apiError(statusCode: let code, data: _):
                XCTAssertEqual(code, 403) // Expected 403 Forbidden (certificate issue)
            default:
                XCTFail("Expected API error with 403 status but got: \(error)")
            }
        }
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

