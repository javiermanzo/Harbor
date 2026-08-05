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
        let request = try await HURLBuilder.buildUrlRequest(request: service)

        XCTAssertEqual(request.url, url)
        let contentType = try XCTUnwrap(request.allHTTPHeaderFields?["Content-Type"])
        XCTAssert(contentType.contains("Boundary-"))
    }

    func testBuildRequestWithEmptyMultipartBodyParameters() async throws {
        let service = MockPostBodyRequest(url: "https://example.com", bodyParameters: nil, bodyType: .multipart)

        let url = URL(string: service.url)
        let request = try await HURLBuilder.buildUrlRequest(request: service)

        XCTAssertEqual(request.url, url)
        XCTAssertNil(request.allHTTPHeaderFields?["Content-Type"])
    }

    func testBuildRequestWithJsonBodyType() async throws {
        let service = MockPostBodyRequest(url: "https://example.com", bodyParameters: ["foo": "bar"], bodyType: .json)
        let expectedContentType = "application/json"

        let url = URL(string: service.url)
        let request = try await HURLBuilder.buildUrlRequest(request: service)

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], expectedContentType)
    }

    func testMultipartRejectsNewlineInName() async {
        XCTAssertThrowsError(try HURLBuilder.convertFormField(named: "na\r\nme", value: "value", using: "Boundary-test")) { error in
            guard case HRequestError.malformedRequest = error else {
                return XCTFail("Expected malformedRequest but got: \(error)")
            }
        }
    }

    func testMultipartRejectsNewlineInValue() async {
        XCTAssertThrowsError(try HURLBuilder.convertFormField(named: "name", value: "va\r\nlue", using: "Boundary-test")) { error in
            guard case HRequestError.malformedRequest = error else {
                return XCTFail("Expected malformedRequest but got: \(error)")
            }
        }
    }

    func testMultipartRejectsQuoteInName() async {
        XCTAssertThrowsError(try HURLBuilder.convertFormField(named: "na\"me", value: "value", using: "Boundary-test")) { error in
            guard case HRequestError.malformedRequest = error else {
                return XCTFail("Expected malformedRequest but got: \(error)")
            }
        }
    }

    func testMultipartRejectsBoundaryInValue() async {
        XCTAssertThrowsError(try HURLBuilder.convertFormField(named: "name", value: "xxBoundary-testxx", using: "Boundary-test")) { error in
            guard case HRequestError.malformedRequest = error else {
                return XCTFail("Expected malformedRequest but got: \(error)")
            }
        }
    }

    func testMultipartBodyParametersStringifyScalars() async throws {
        let service = MockPostBodyRequest(url: "https://example.com", bodyParameters: ["count": 42, "flag": true], bodyType: .multipart)

        let request = try await HURLBuilder.buildUrlRequest(request: service)
        let body = try XCTUnwrap(request.httpBody)
        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertTrue(bodyString.contains("name=\"count\""))
        XCTAssertTrue(bodyString.contains("\r\n42\r\n"))
        XCTAssertTrue(bodyString.contains("name=\"flag\""))
        XCTAssertTrue(bodyString.contains("\r\ntrue\r\n"))
    }

    func testMultipartBodyWithFile() async throws {
        let fileContents = "multipart file contents"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-test-\(UUID().uuidString).txt")
        try Data(fileContents.utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let service = MockPostBodyRequest(url: "https://example.com", multipartBody: [
            "field": .text("hello"),
            "file": .file(url: fileURL, mimeType: "text/plain", fileName: "test.txt"),
        ])

        let request = try await HURLBuilder.buildUrlRequest(request: service)

        let contentType = try XCTUnwrap(request.allHTTPHeaderFields?["Content-Type"])
        XCTAssertTrue(contentType.contains("multipart/form-data"))

        let body = try XCTUnwrap(request.httpBody)
        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"field\""))
        XCTAssertTrue(bodyString.contains("\r\nhello\r\n"))
        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"file\"; filename=\"test.txt\""))
        XCTAssertTrue(bodyString.contains("Content-Type: text/plain"))
        XCTAssertTrue(bodyString.contains(fileContents))
    }

    func testMultipartBodyWithUnreadableFileThrows() async throws {
        let missingFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-missing-\(UUID().uuidString).txt")
        let service = MockPostBodyRequest(url: "https://example.com", multipartBody: [
            "file": .file(url: missingFileURL, mimeType: nil, fileName: nil),
        ])

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
