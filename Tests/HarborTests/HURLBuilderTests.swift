//
//  HURLBuilderTests.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import XCTest
@testable import Harbor

@HRequestManagerActor
final class HURLBuilderTests: XCTestCase {

    func testPathParameterEncoding() async throws {
        let baseUrl = "https://api.example.com/users/{id}/details"
        // '?' should be encoded to prevent query injection
        // '/' is allowed in urlPathAllowed so it might remain depending on the implementation details,
        // but '?' is definitely not allowed in path without encoding if we want it to be part of the segment.
        let pathParameters = ["id": "user?name=test"]

        let url = try HURLBuilder.compositeURL(url: baseUrl, pathParameters: pathParameters)

        // We expect '?' to be encoded as %3F
        XCTAssertEqual(url.absoluteString, "https://api.example.com/users/user%3Fname=test/details")
    }

    func testPathParameterSimple() async throws {
        let baseUrl = "https://api.example.com/users/{id}"
        let pathParameters = ["id": "123"]

        let url = try HURLBuilder.compositeURL(url: baseUrl, pathParameters: pathParameters)

        XCTAssertEqual(url.absoluteString, "https://api.example.com/users/123")
    }

    func testQueryParametersMergeWithExistingQuery() async throws {
        let baseUrl = "https://api.example.com/x?foo=bar"
        let queryParameters = ["page": "1"]

        let url = try HURLBuilder.compositeURL(url: baseUrl, queryParameters: queryParameters)

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try XCTUnwrap(components.queryItems)
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "foo", value: "bar")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "page", value: "1")))
    }

    func testPathParameterWithTraversalSegmentThrows() async {
        let baseUrl = "https://api.example.com/users/{id}"

        for value in ["../admin", "foo/../../bar", ".."] {
            XCTAssertThrowsError(try HURLBuilder.compositeURL(url: baseUrl, pathParameters: ["id": value])) { error in
                guard case HRequestError.malformedRequest = error else {
                    return XCTFail("Expected malformedRequest but got: \(error)")
                }
            }
        }
    }

    func testCompositeURLIsDeterministic() async throws {
        let baseUrl = "https://api.example.com/x?foo=bar"
        let queryParameters = ["page": "1", "limit": "10", "sort": "desc"]

        let first = try HURLBuilder.compositeURL(url: baseUrl, queryParameters: queryParameters)
        for _ in 0 ..< 10 {
            let url = try HURLBuilder.compositeURL(url: baseUrl, queryParameters: queryParameters)
            XCTAssertEqual(url.absoluteString, first.absoluteString)
        }
    }

    func testBuildUrlRequestFailureSurfacesReason() async {
        let service = MockInvalidRequest(url: "https://api.example.com")

        do {
            _ = try await HURLBuilder.buildUrlRequest(request: service)
            XCTFail("Expected buildUrlRequest to throw")
        } catch HRequestError.malformedRequest(let reason) {
            XCTAssertFalse(reason?.isEmpty ?? true, "The error should carry a concrete reason")
        } catch {
            XCTFail("Expected malformedRequest but got: \(error)")
        }
    }
}
