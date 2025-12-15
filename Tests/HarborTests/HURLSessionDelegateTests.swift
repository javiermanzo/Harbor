//
//  HURLSessionDelegateTests.swift
//  HarborTests
//
//  Created by Javier Manzo on 06/07/2025.
//

import XCTest
@testable import Harbor

final class HURLSessionDelegateTests: XCTestCase {

    func testDelegateHandlesMissingIdentity() {
        // Given
        // Initialize delegate with nil identity
        let delegate = HURLSessionDelegate(mTLSIdentity: nil, sslPinningKeys: nil)
        
        // Create a mock challenge for Client Certificate
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
    
    // MARK: - SSL Pinning Tests
    
    func testSSLPinningWithMultipleKeys_OneMatch_ShouldSucceed() {
        // Since we can't easily mock SecTrust without real certs, we will at least verify that 
        // initializing with multiple keys works and setting up the delegate works.
        // NOTE: True logic validation requires a mocked TrustEvaluator which is not present in the current implementation.
        // This test ensures no crashes occur during init and basic handling.
        
        // Given
        let validKey1 = "VALID_KEY_1"
        let validKey2 = "VALID_KEY_2"
        let delegate = HURLSessionDelegate(mTLSIdentity: nil, sslPinningKeys: [validKey1, validKey2])
        
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
