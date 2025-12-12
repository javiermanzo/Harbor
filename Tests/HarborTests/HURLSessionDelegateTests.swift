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
        let delegate = HURLSessionDelegate(mTLS: mTLS, sslPinningSHA256: nil)
        
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
}

// Mock sender to satisfy URLAuthenticationChallenge
final class MockURLSessionSender: NSObject, URLAuthenticationChallengeSender, @unchecked Sendable {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}

