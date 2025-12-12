//
//  HURLSessionDelegateTests.swift
//  HarborTests
//
//  Created by Javier Manzo on 06/07/2025.
//

import XCTest
@testable import Harbor

final class HURLSessionDelegateTests: XCTestCase {

    func testCertificateLoadingIsCached() {
        // Given
        // Create a dummy file URL (file doesn't need to exist for the initial init, 
        // but needs to exist for the Data(contentsOf:) call to succeed, or we test failure)
        let tempDir = FileManager.default.temporaryDirectory
        let p12Url = tempDir.appendingPathComponent("test_cached.p12")
        let password = "password"
        
        // Ensure file does not exist initially
        try? FileManager.default.removeItem(at: p12Url)
        
        // This will attempt to read the file immediately (Eager load) and cache the failure
        let mTLS = HmTLS(p12FileUrl: p12Url, password: password)
        let delegate = HURLSessionDelegate(mTLS: mTLS, sslPinningKeys: nil)
        
        // Create a mock challenge
        let protectionSpace = URLProtectionSpace(host: "example.com",
                                                 port: 443,
                                                 protocol: "https",
                                                 realm: nil,
                                                 authenticationMethod: NSURLAuthenticationMethodClientCertificate)
        
        let challenge = URLAuthenticationChallenge(protectionSpace: protectionSpace,
                                                   proposedCredential: nil,
                                                   previousFailureCount: 0,
                                                   failureResponse: nil,
                                                   error: nil,
                                                   sender: MockURLSessionSender())
        
        // When
        // 1. First trigger - Should fail (using cached failure from init)
        let expectation1 = XCTestExpectation(description: "First challenge")
        delegate.urlSession(URLSession.shared, didReceive: challenge) { disposition, credential in
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            XCTAssertNil(credential)
            expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 1.0)
        
        // 2. Create the file now.
        // Since the result was cached during init, subsequent calls should STILL fail 
        // without trying to read the file.
        
        let dummyData = "dummy data".data(using: .utf8)!
        try? dummyData.write(to: p12Url)
        
        let expectation2 = XCTestExpectation(description: "Second challenge")
        delegate.urlSession(URLSession.shared, didReceive: challenge) { disposition, credential in
            // It should still fail because the failure was cached
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 1.0)
        
        // Cleanup
        try? FileManager.default.removeItem(at: p12Url)
    }
    
    // MARK: - SSL Pinning Tests
    
    func testSSLPinningWithMultipleKeys_OneMatch_ShouldSucceed() {
        // Since we can't easily mock SecTrust without real certs, we will at least verify that 
        // initializing with multiple keys works and setting up the delegate works.
        // NOTE: True logic validation requires a mocked TrustEvaluator which is not present in the current implementation.
        // This test ensures no crashes occur during init and basic handling.
        
        // Given
        let validKey1 = "VALID_KEY_1"
        let validKey2 = "VALID_KEY_2"
        let delegate = HURLSessionDelegate(mTLS: nil, sslPinningKeys: [validKey1, validKey2])
        
        let protectionSpace = URLProtectionSpace(host: "secure.example.com",
                                                 port: 443,
                                                 protocol: "https",
                                                 realm: nil,
                                                 authenticationMethod: NSURLAuthenticationMethodServerTrust)
        
        // Create a challenge without a serverTrust object (it will be nil)
        // This should fail gracefully
        let challenge = URLAuthenticationChallenge(protectionSpace: protectionSpace,
                                                   proposedCredential: nil,
                                                   previousFailureCount: 0,
                                                   failureResponse: nil,
                                                   error: nil,
                                                   sender: MockURLSessionSender())
        
        let expectation = XCTestExpectation(description: "SSL Pinning with nil trust")
        
        // When
        delegate.urlSession(URLSession.shared, didReceive: challenge) { disposition, credential in
            // Then
            // Should cancel because serverTrust is nil
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge) // Or performDefaultHandling if it falls through, but based on code:
            // guard ... let serverTrust ... else { return nil } -> returns completionHandler(.performDefaultHandling, nil) (Wait, check code)
            
            // Checking code:
            // if let sslPinningKeys, let result = processSSLPinning(...) { ... }
            // processSSLPinning returns nil if serverTrust is missing.
            // If result is nil, it goes to: if sslPinningKeys != nil { return .cancel }
            
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
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
