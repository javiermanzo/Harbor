import XCTest
@testable import Harbor

@HRequestManagerActor
final class HarborManagerTests: XCTestCase {

    func testShouldAddSinglePathParameterCorrectlyToURL() async throws {
        // Given
        let baseUrl = "https://api.github.com/users/{USER}/"
        let expectedURL = "https://api.github.com/users/OmarJalil/"

        // When
        let url = try HURLBuilder.compositeURL(url: baseUrl, pathParameters: ["USER": "OmarJalil"], queryParameters: nil)

        // Then
        XCTAssertEqual(expectedURL, url.absoluteString)
    }

    func testShouldAddMultiplePathParametersCorrectlyToURL() async throws {
        // Given
        let baseUrl = "https://api.github.com/users/{USER}/following/{FOLLOWS}/"
        let expectedURL = "https://api.github.com/users/OmarJalil/following/javiermanzo/"

        // When
        let url = try HURLBuilder.compositeURL(url: baseUrl, pathParameters: ["FOLLOWS": "javiermanzo", "USER": "OmarJalil"], queryParameters: nil)

        // Then
        XCTAssertEqual(expectedURL, url.absoluteString)
    }

    func testBuildGetRequest() async throws {
        // Given
        let service = MockGetRequest<String>(url: "https://example.com", queryParameters: ["id": "123", "sort": "desc"])

        // When
        let request = try await HURLBuilder.buildUrlRequest(request: service)
        
        // Then
        XCTAssertEqual(request.url?.absoluteString, "https://example.com?id=123&sort=desc")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testBuildPostRequest() async throws {
        // Given
        let service = MockPostRequest(url: "https://example.com", bodyParameters: ["name": "John"])

        // When
        let request = try await HURLBuilder.buildUrlRequest(request: service)

        // Then
        XCTAssertEqual(request.url?.absoluteString, "https://example.com")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/json")
        let httpBody = try HURLBuilder.dataBody(params: ["name": "John"], type: .json, boundary: nil)
        XCTAssertEqual(request.httpBody, httpBody)
    }

    func testBuildInvalidRequest() async throws {
        // Given
        let service = MockInvalidRequest()

        // When/Then
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
    
    func testRetryLogicExecution() async throws {
        // Given
        await Harbor.removeAllMocks()
        
        // Mock that will return 500 error to trigger retries
        let mock = await HMock(request: MockGetRequestWithRetries<MockModel>.self, statusCode: 500)
        await Harbor.register(mock: mock)
        
        // When
        let service = MockGetRequestWithRetries<MockModel>(retries: 2, url: "https://api.example.com/test")
        let response = await service.request()
        
        // Then
        switch response {
        case .success:
            XCTFail("Expected error but got success")
        case .error(let error):
            // Should be API error after retries exhausted
            switch error {
            case .api(statusCode: let code, data: _):
                XCTAssertEqual(code, 500)
            default:
                XCTFail("Expected API error but got: \(error)")
            }
        }
        
        await Harbor.removeAllMocks()
    }
    
    func testRetryLogicEventualSuccess() async throws {
        // Given
        await Harbor.removeAllMocks()
        
        let mockResponse = MockModel(quote: "Success after retry")
        let jsonData = try JSONEncoder().encode(mockResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        // Mock that will succeed
        let mock = await HMock(request: MockGetRequestWithRetries<MockModel>.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        // When
        let service = MockGetRequestWithRetries<MockModel>(retries: 2, url: "https://api.example.com/test")
        let response = await service.request()
        
        // Then
        switch response {
        case .success(let result):
            XCTAssertEqual(result.quote, "Success after retry")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
        
        await Harbor.removeAllMocks()
    }
}
