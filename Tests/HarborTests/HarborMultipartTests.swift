//
//  HarborMultipartTests.swift
//  
//
//  Created by Jalil on 18/06/24.
//

import XCTest
@testable import Harbor

final class HarborMultipartTests: XCTestCase {

    func testBuildRequestWithMultipartBodyType() throws {
        let service = MockPostMultipartRequestService(url: "https://example.com", bodyParameters: ["foo": "bar"], bodyType: .multipart)

        let url = try XCTUnwrap(URL(string: service.url))
        let request = try XCTUnwrap(HRequestManager.buildUrlRequest(request: service))

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.httpMethod, request.httpMethod)
        let contentType = try XCTUnwrap(request.allHTTPHeaderFields!["Content-Type"])
        XCTAssert(contentType.contains("Boundary-"))
    }

    func testBuildRequestWithEmptyMultipartBodyParameters() throws {
        let service = MockPostMultipartRequestService(url: "https://example.com", bodyParameters: nil, bodyType: .multipart)

        let url = try XCTUnwrap(URL(string: service.url))
        let request = try XCTUnwrap(HRequestManager.buildUrlRequest(request: service))

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.httpMethod, request.httpMethod)
        XCTAssertNil(request.allHTTPHeaderFields?["Content-Type"])
    }

    func testBuildRequestWithNonMultipartBodyType() throws {
        let service = MockPostMultipartRequestService(url: "https://example.com", bodyParameters: ["foo": "bar"], bodyType: .json)
        let expectedContentType = "application/json"

        let url = try XCTUnwrap(URL(string: service.url))
        let request = try XCTUnwrap(HRequestManager.buildUrlRequest(request: service))

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.httpMethod, request.httpMethod)
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], expectedContentType)
    }

}
