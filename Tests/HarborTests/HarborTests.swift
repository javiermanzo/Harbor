import XCTest
@testable import Harbor

final class HarborTests: XCTestCase {

    func testShouldAddSinglePathParameterCorrectlyToURL() throws {
        // Given
        let baseUrl = "example.com/api/v1/users/{ID}"
        let expectedURL = "example.com/api/v1/users/1"

        // When
        let url = HRequestManager.compositeURL(url: baseUrl, pathParameters: ["ID": "1"], queryParameters: nil)

        // Then
        XCTAssertEqual(expectedURL, url?.absoluteString)
    }

    func testShouldAddMultiplePathParametersCorrectlyToURL() throws {
        // Given
        let baseUrl = "example.com/api/v1/users/{ID}/profile/{USERNAME}/"
        let expectedURL = "example.com/api/v1/users/1/profile/jalil/"

        // When
        let url = HRequestManager.compositeURL(url: baseUrl, pathParameters: ["USERNAME": "jalil", "ID": "1"], queryParameters: nil)

        // Then
        XCTAssertEqual(expectedURL, url?.absoluteString)
    }

    func testBuildGetRequest() {
        // Given
        let service = MockGetRequestService(url: "https://example.com", queryParameters: ["id": "123", "sort": "desc"])

        // When
        let request = HRequestManager.buildUrlRequest(request: service)
        // Then
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.url?.absoluteString, "https://example.com?id=123&sort=desc")
        XCTAssertEqual(request?.httpMethod, "GET")
    }

    func testBuildPostRequest() {
        // Given
        let service = MockPostRequestService(url: "https://example.com", bodyParameters: ["name": "John"])

        // When
        let request = HRequestManager.buildUrlRequest(request: service)

        // Then
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.url?.absoluteString, "https://example.com")
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.allHTTPHeaderFields?["Content-Type"], "application/json")
        XCTAssertEqual(request?.httpBody, HRequestManager.dataBody(params: ["name": "John"], type: .json))
    }

    func testBuildInvalidRequest() {
        // Given
        let service = MockInvalidRequestService()

        // When
        let request = HRequestManager.buildUrlRequest(request: service)

        // Then
        XCTAssertNil(request)
    }
}
