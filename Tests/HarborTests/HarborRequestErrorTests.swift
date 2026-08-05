//
//  HarborRequestErrorTests.swift
//  Harbor
//
//  Tests for URLError mapping and error descriptions.
//

import XCTest
@testable import Harbor

final class HarborRequestErrorTests: XCTestCase {

    // MARK: - URLError Mapping

    /// Stable name per case, so mappings can be asserted without requiring `Equatable`
    /// on the wrapped payloads (`api` data, `codable` error, `networkFailure` URLError).
    private func caseName(_ error: HRequestError) -> String {
        switch error {
        case .api: return "api"
        case .invalidHttpResponse: return "invalidHttpResponse"
        case .invalidRequest: return "invalidRequest"
        case .authProviderNeeded: return "authProviderNeeded"
        case .authNeeded: return "authNeeded"
        case .codable: return "codable"
        case .noConnection: return "noConnection"
        case .malformedRequest: return "malformedRequest"
        case .timeout: return "timeout"
        case .cannotFindHost: return "cannotFindHost"
        case .cancelled: return "cancelled"
        case .certificate: return "certificate"
        case .noCachedDataFound: return "noCachedDataFound"
        case .networkFailure: return "networkFailure"
        }
    }

    func testMapURLErrorKnownCodes() {
        let expectations: [(URLError.Code, String)] = [
            (.cancelled, "cancelled"),
            (.badURL, "malformedRequest"),
            (.cannotConnectToHost, "cannotFindHost"),
            (.cannotFindHost, "cannotFindHost"),
            (.dnsLookupFailed, "cannotFindHost"),
            (.serverCertificateUntrusted, "certificate"),
            (.timedOut, "timeout"),
            (.notConnectedToInternet, "noConnection"),
            (.networkConnectionLost, "noConnection"),
            (.dataNotAllowed, "noConnection"),
            (.internationalRoamingOff, "noConnection"),
            (.resourceUnavailable, "invalidHttpResponse"),
        ]

        for (code, expected) in expectations {
            let mapped = HRequestError.mapURLError(URLError(code))
            XCTAssertEqual(caseName(mapped), expected, "Unexpected mapping for \(code)")
        }
    }

    func testMapURLErrorUnknownCodeFallsBackToNetworkFailure() {
        let unmappedCodes: [URLError.Code] = [.badServerResponse, .redirectToNonExistentLocation, .unknown]

        for code in unmappedCodes {
            let urlError = URLError(code)
            let mapped = HRequestError.mapURLError(urlError)

            guard case .networkFailure(let wrapped) = mapped else {
                XCTFail("Expected .networkFailure for \(code), got \(caseName(mapped))")
                continue
            }
            XCTAssertEqual(wrapped.code, code)
        }
    }

    // MARK: - Error Descriptions

    func testAPIDescriptionIncludesBoundedBodyPreview() {
        // Given a UTF-8 body longer than the preview limit
        let body = String(repeating: "a", count: 600)
        let error = HRequestError.api(statusCode: 500, data: Data(body.utf8))

        // Then the description contains the status code and the first 500 characters only
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("500"), "Description should contain the status code")
        XCTAssertTrue(description.contains(String(repeating: "a", count: 500)))
        XCTAssertFalse(description.contains(String(repeating: "a", count: 501)),
                       "Body preview should be truncated to 500 characters")
    }

    func testAPIDescriptionWithShortBodyIsNotTruncated() {
        let error = HRequestError.api(statusCode: 404, data: Data("not found".utf8))

        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("404"))
        XCTAssertTrue(description.contains("not found"))
    }

    func testAPIDescriptionWithEmptyBodyOmitsPreview() {
        let error = HRequestError.api(statusCode: 500, data: Data())

        XCTAssertEqual(error.errorDescription, "API error with status code: 500")
    }

    func testAPIDescriptionWithNonUTF8BodyNotesByteCount() {
        let data = Data([0xFF, 0xFE, 0x00, 0xD8])
        let error = HRequestError.api(statusCode: 502, data: data)

        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("502"))
        XCTAssertTrue(description.contains("\(data.count) bytes"),
                      "Non-UTF-8 bodies should be described by their byte count")
    }

    func testCodableDescriptionIncludesUnderlyingError() {
        let decodingError = DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "expected a JSON object")
        )
        let error = HRequestError.codable(modelName: "User", error: decodingError)

        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("User"))
        XCTAssertTrue(description.contains("expected a JSON object"),
                      "Description should include the DecodingError context")
    }

    func testNetworkFailureDescriptionIncludesCodeAndMessage() {
        let urlError = URLError(.badServerResponse)
        let error = HRequestError.networkFailure(urlError)

        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("\(URLError.Code.badServerResponse.rawValue)"))
        XCTAssertTrue(description.contains(urlError.localizedDescription))
    }
}
