//
//  HarborBodyTests.swift
//
//
//  Created by Jalil on 18/06/24.
//

import XCTest
@testable import Harbor

@HRequestManagerActor
final class HarborBodyTests: XCTestCase {

    func testBuildRequestWithMultipartBodyType() async throws {
        let service = MockPostBodyRequest(url: "https://example.com", bodyParameters: ["foo": "bar"], bodyType: .multipart)

        let url = URL(string: service.url)
        let request = HRequestManager.buildUrlRequest(request: service)

        XCTAssertEqual(request?.url, url)
        let contentType = try XCTUnwrap(request?.allHTTPHeaderFields!["Content-Type"])
        XCTAssert(contentType.contains("Boundary-"))
    }

    func testBuildRequestWithEmptyMultipartBodyParameters() async throws {
        let service = MockPostBodyRequest(url: "https://example.com", bodyParameters: nil, bodyType: .multipart)

        let url = URL(string: service.url)
        let request = HRequestManager.buildUrlRequest(request: service)

        XCTAssertEqual(request?.url, url)
        XCTAssertNil(request?.allHTTPHeaderFields?["Content-Type"])
    }

    func testBuildRequestWithJsonBodyType() async throws {
        let service = MockPostBodyRequest(url: "https://example.com", bodyParameters: ["foo": "bar"], bodyType: .json)
        let expectedContentType = "application/json"

        let url = URL(string: service.url)
        let request = HRequestManager.buildUrlRequest(request: service)

        XCTAssertEqual(request?.url, url)
        XCTAssertEqual(request?.allHTTPHeaderFields?["Content-Type"], expectedContentType)
    }

}
