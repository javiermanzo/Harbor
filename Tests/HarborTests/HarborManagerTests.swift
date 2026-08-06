import XCTest
@testable import Harbor

@HRequestManagerActor
final class HarborManagerTests: XCTestCase {

    func testShouldAddSinglePathParameterCorrectlyToURL() async throws {
        let baseUrl = "https://api.github.com/users/{USER}/"
        let expectedURL = "https://api.github.com/users/OmarJalil/"

        let url = try HURLBuilder.compositeURL(url: baseUrl, pathParameters: ["USER": "OmarJalil"], queryParameters: nil)

        XCTAssertEqual(expectedURL, url.absoluteString)
    }

    func testShouldAddMultiplePathParametersCorrectlyToURL() async throws {
        let baseUrl = "https://api.github.com/users/{USER}/following/{FOLLOWS}/"
        let expectedURL = "https://api.github.com/users/OmarJalil/following/javiermanzo/"

        let url = try HURLBuilder.compositeURL(url: baseUrl, pathParameters: ["FOLLOWS": "javiermanzo", "USER": "OmarJalil"], queryParameters: nil)

        XCTAssertEqual(expectedURL, url.absoluteString)
    }

    func testBuildGetRequest() async throws {
        let service = MockGetRequest<String>(url: "https://example.com", queryParameters: ["id": "123", "sort": "desc"])

        let request = try await HURLBuilder.buildUrlRequest(request: service)

        XCTAssertEqual(request.url?.absoluteString, "https://example.com?id=123&sort=desc")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testBuildPostRequest() async throws {
        let service = MockPostRequest(url: "https://example.com", bodyParameters: ["name": "John"])

        let request = try await HURLBuilder.buildUrlRequest(request: service)

        XCTAssertEqual(request.url?.absoluteString, "https://example.com")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/json")
        let httpBody = try HURLBuilder.dataBody(params: ["name": "John"], type: .json, boundary: nil)
        XCTAssertEqual(request.httpBody, httpBody)
    }

    func testBuildInvalidRequest() async throws {
        let service = MockInvalidRequest()

        do {
            _ = try await HURLBuilder.buildUrlRequest(request: service)
            XCTFail("Expected buildUrlRequest to throw")
        } catch let error as HRequestError {
            guard case .malformedRequest = error else {
                return XCTFail("Expected malformedRequest but got: \(error)")
            }
        } catch {
            XCTFail("Expected HRequestError but got: \(error)")
        }
    }
}
