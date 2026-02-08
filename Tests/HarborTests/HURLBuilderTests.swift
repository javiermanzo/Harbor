//
//  HURLBuilderTests.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import XCTest
@testable import Harbor

final class HURLBuilderTests: XCTestCase {

    func testPathParameterEncoding() {
        let baseUrl = "https://api.example.com/users/{id}/details"
        // '?' should be encoded to prevent query injection
        // '/' is allowed in urlPathAllowed so it might remain depending on the implementation details,
        // but '?' is definitely not allowed in path without encoding if we want it to be part of the segment.
        let pathParameters = ["id": "user?name=test"]
        
        let url = HURLBuilder.compositeURL(url: baseUrl, pathParameters: pathParameters)
        
        // We expect '?' to be encoded as %3F
        XCTAssertEqual(url?.absoluteString, "https://api.example.com/users/user%3Fname=test/details")
    }

    func testPathParameterSimple() {
        let baseUrl = "https://api.example.com/users/{id}"
        let pathParameters = ["id": "123"]
        
        let url = HURLBuilder.compositeURL(url: baseUrl, pathParameters: pathParameters)
        
        XCTAssertEqual(url?.absoluteString, "https://api.example.com/users/123")
    }
}
