//
//  HarborRequestProtocolShapeTests.swift
//  HarborTests
//
//  `headerParameters` and `bodyParameters` are get-only requirements: plain `Sendable`
//  structs with computed properties conform, and stored `let`/`var` conformers still do.
//

import XCTest
@testable import Harbor

/// A plain `Sendable` struct (no `@unchecked`) with computed, get-only body and headers.
/// Compiling this type is the regression test: with `{ get set }` requirements it did not conform.
private struct ComputedBodyPostRequest: HPostRequestProtocol {
    let name: String
    var url: String { "https://api.example.com/users" }
    var headerParameters: [String: String]? { ["X-Client": "tests"] }
    var bodyParameters: [String: Any]? { ["name": name] }
}

/// Same shape for PUT and PATCH, with `let` headers.
private struct ComputedBodyPutRequest: HPutRequestProtocol {
    let url = "https://api.example.com/users/1"
    let headerParameters: [String: String]? = ["X-Client": "tests"]
    var bodyParameters: [String: Any]? { ["name": "put"] }
}

private struct ComputedBodyPatchRequest: HPatchRequestProtocol {
    let url = "https://api.example.com/users/1"
    var bodyParameters: [String: Any]? { ["name": "patch"] }
}

/// Stored `var` conformers keep compiling (a stored `[String: Any]` still needs `@unchecked Sendable`).
private struct StoredBodyPostRequest: HPostRequestProtocol, @unchecked Sendable {
    let url = "https://api.example.com/users"
    var headerParameters: [String: String]?
    var bodyParameters: [String: Any]?
}

@HRequestManagerActor
final class HarborRequestProtocolShapeTests: XCTestCase {

    private func requireSendable<T: Sendable>(_ value: T) -> T { value }

    func testComputedGetOnlyPropertiesConformAndAreUsed() async throws {
        let request = requireSendable(ComputedBodyPostRequest(name: "Ada"))

        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)

        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-Client"), "tests")
        let body = try XCTUnwrap(urlRequest.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["name": "Ada"])
    }

    func testPutAndPatchWithComputedBodiesConform() async throws {
        let put = try await HURLBuilder.buildUrlRequest(request: requireSendable(ComputedBodyPutRequest()))
        let patch = try await HURLBuilder.buildUrlRequest(request: requireSendable(ComputedBodyPatchRequest()))

        XCTAssertEqual(put.httpMethod, "PUT")
        XCTAssertEqual(put.value(forHTTPHeaderField: "X-Client"), "tests")
        XCTAssertEqual(patch.httpMethod, "PATCH")
        XCTAssertNotNil(patch.httpBody)
    }

    func testStoredVarConformersStillWork() async throws {
        var request = StoredBodyPostRequest()
        request.headerParameters = ["X-Stored": "1"]
        request.bodyParameters = ["stored": true]

        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)

        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-Stored"), "1")
        XCTAssertNotNil(urlRequest.httpBody)
    }

    func testDefaultHeaderParametersIsNil() async {
        XCTAssertNil(ComputedBodyPatchRequest().headerParameters)
    }
}
