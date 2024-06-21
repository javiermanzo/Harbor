import XCTest
@testable import Harbor

final class HarborTests: XCTestCase {

    func testShouldAddSinglePathParameterCorrectlyToURL() throws {
        // Given
        let baseUrl = "https://api.github.com/users/{USER}/"
        let expectedURL = "https://api.github.com/users/OmarJalil/"

        // When
        let url = HRequestManager.compositeURL(url: baseUrl, pathParameters: ["USER": "OmarJalil"], queryParameters: nil)

        // Then
        XCTAssertEqual(expectedURL, url?.absoluteString)
    }

    func testShouldAddMultiplePathParametersCorrectlyToURL() throws {
        // Given
        let baseUrl = "https://api.github.com/users/{USER}/following/{FOLLOWS}/"
        let expectedURL = "https://api.github.com/users/OmarJalil/following/javiermanzo/"

        // When
        let url = HRequestManager.compositeURL(url: baseUrl, pathParameters: ["FOLLOWS": "javiermanzo", "USER": "OmarJalil"], queryParameters: nil)

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
