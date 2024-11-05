import XCTest
@testable import Harbor

final class HarborTests: XCTestCase {

    func testShouldAddSinglePathParameterCorrectlyToURL() async throws {
        // Given
        let baseUrl = "https://api.github.com/users/{USER}/"
        let expectedURL = "https://api.github.com/users/OmarJalil/"

        // When
        let url = await HRequestManager.compositeURL(url: baseUrl, pathParameters: ["USER": "OmarJalil"], queryParameters: nil)

        // Then
        XCTAssertEqual(expectedURL, url?.absoluteString)
    }

    func testShouldAddMultiplePathParametersCorrectlyToURL() async throws {
        // Given
        let baseUrl = "https://api.github.com/users/{USER}/following/{FOLLOWS}/"
        let expectedURL = "https://api.github.com/users/OmarJalil/following/javiermanzo/"

        // When
        let url = await HRequestManager.compositeURL(url: baseUrl, pathParameters: ["FOLLOWS": "javiermanzo", "USER": "OmarJalil"], queryParameters: nil)

        // Then
        XCTAssertEqual(expectedURL, url?.absoluteString)
    }

    func testBuildGetRequest() async throws {
        // Given
        let service = MockGetRequestService(url: "https://example.com", queryParameters: ["id": "123", "sort": "desc"])

        // When
        let request = await HRequestManager.buildUrlRequest(request: service)
        
        // Then
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.url?.absoluteString, "https://example.com?id=123&sort=desc")
        XCTAssertEqual(request?.httpMethod, "GET")
    }

    func testBuildPostRequest() async throws {
        // Given
        let service = MockPostRequestService(url: "https://example.com", bodyParameters: ["name": "John"])

        // When
        let request = await HRequestManager.buildUrlRequest(request: service)

        // Then
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.url?.absoluteString, "https://example.com")
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.allHTTPHeaderFields?["Content-Type"], "application/json")
        let httpBody = await HRequestManager.dataBody(params: ["name": "John"], type: .json)
        XCTAssertEqual(request?.httpBody, httpBody)
    }

    func testBuildInvalidRequest() async throws {
        // Given
        let service = MockInvalidRequestService()

        // When
        let request = await HRequestManager.buildUrlRequest(request: service)

        // Then
        XCTAssertNil(request)
    }
}
