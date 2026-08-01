//
//  HarborDebugTests.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import XCTest
@testable import Harbor

// Helper function for async XCTAssertNoThrow
func XCTAssertNoThrowAsync<T>(_ expression: @autoclosure () async throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await expression()
    } catch {
        XCTFail("Unexpected error thrown: \(error). \(message())", file: file, line: line)
    }
}

final class HarborDebugTests: XCTestCase {
    
    override func setUp() async throws {
        await Harbor.removeAllMocks()
        await Harbor.setMocksOnlyInDebug(false)
        await Harbor.setLogSensitiveHeaders(false)
        await Harbor.setCustomURLSession(URLSession.shared)
    }

    override func tearDown() async throws {
        await Harbor.removeAllMocks()
        await Harbor.setLogSensitiveHeaders(false)
        await Harbor.setCustomURLSession(URLSession.shared)
    }
    
    // MARK: - Debug Type Tests
    
    func testDebugTypeNone() {
        let request = TestDebugRequest(debugType: .none)
        XCTAssertEqual(request.debugType, .none)
    }
    
    func testDebugTypeRequest() {
        let request = TestDebugRequest(debugType: .request)
        XCTAssertEqual(request.debugType, .request)
    }
    
    func testDebugTypeResponse() {
        let request = TestDebugRequest(debugType: .response)
        XCTAssertEqual(request.debugType, .response)
    }
    
    func testDebugTypeRequestAndResponse() {
        let request = TestDebugRequest(debugType: .requestAndResponse)
        XCTAssertEqual(request.debugType, .requestAndResponse)
    }
    
    // MARK: - cURL Generation Tests
    
    func testGenerateCurlBasicGetRequest() async {
        let request = TestDebugRequest(debugType: .request)
        let urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)
        
        let curl = await request.generateCurl(urlRequest: urlRequest)
        
        XCTAssertTrue(curl.contains("$ curl -v"))
        XCTAssertTrue(curl.contains("https://api.example.com/test"))
        XCTAssertFalse(curl.contains("-X GET"), "GET method should not be explicitly specified")
    }
    
    func testGenerateCurlPostRequest() async {
        let request = TestDebugRequest(debugType: .request)
        var urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)
        urlRequest.httpMethod = "POST"
        
        let curl = await request.generateCurl(urlRequest: urlRequest)
        
        XCTAssertTrue(curl.contains("$ curl -v"))
        XCTAssertTrue(curl.contains("-X POST"))
        XCTAssertTrue(curl.contains("https://api.example.com/test"))
    }
    
    func testGenerateCurlWithHeaders() async {
        let request = TestDebugRequest(debugType: .request)
        var urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer token123", forHTTPHeaderField: "Authorization")

        let curl = await request.generateCurl(urlRequest: urlRequest)

        XCTAssertTrue(curl.contains("-H \"Content-Type: application/json\""))
        XCTAssertTrue(curl.contains("-H \"Authorization: <redacted>\""))
        XCTAssertFalse(curl.contains("Bearer token123"))
    }
    
    func testGenerateCurlWithBody() async {
        let request = TestDebugRequest(debugType: .request)
        var urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)
        urlRequest.httpMethod = "POST"
        let jsonData = "{\"key\":\"value\"}".data(using: .utf8)!
        urlRequest.httpBody = jsonData
        
        let curl = await request.generateCurl(urlRequest: urlRequest)
        
        XCTAssertTrue(curl.contains("-X POST"))
        XCTAssertTrue(curl.contains("-d \"{\\\"key\\\":\\\"value\\\"}\""))
    }
    
    func testGenerateCurlWithSpecialCharactersInBody() async {
        let request = TestDebugRequest(debugType: .request)
        var urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)
        urlRequest.httpMethod = "POST"
        let jsonData = "{\"message\":\"Hello \\\"world\\\" with quotes\"}".data(using: .utf8)!
        urlRequest.httpBody = jsonData
        
        let curl = await request.generateCurl(urlRequest: urlRequest)
        
        XCTAssertTrue(curl.contains("-X POST"))
        XCTAssertTrue(curl.contains("Hello"))
        XCTAssertTrue(curl.contains("world"))
        XCTAssertTrue(curl.contains("quotes"))
    }
    
    func testGenerateCurlInvalidURL() async {
        let request = TestDebugRequest(debugType: .request)
        let urlRequest = URLRequest(url: URL(string: "invalid-url")!)
        
        let curl = await request.generateCurl(urlRequest: urlRequest)
        
        XCTAssertEqual(curl, "$ curl command could not be created")
    }
    
    func testGenerateCurlWithComplexRequest() async {
        let request = TestDebugRequest(debugType: .request)
        var urlRequest = URLRequest(url: URL(string: "https://api.example.com/users/123?include=profile")!)
        urlRequest.httpMethod = "PATCH"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer abc123", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        let jsonData = "{\"name\":\"John Doe\",\"age\":30}".data(using: .utf8)!
        urlRequest.httpBody = jsonData
        
        let curl = await request.generateCurl(urlRequest: urlRequest)
        
        XCTAssertTrue(curl.contains("$ curl -v"))
        XCTAssertTrue(curl.contains("-X PATCH"))
        XCTAssertTrue(curl.contains("-H \"Content-Type: application/json\""))
        XCTAssertTrue(curl.contains("-H \"Authorization: <redacted>\""))
        XCTAssertFalse(curl.contains("Bearer abc123"))
        XCTAssertTrue(curl.contains("-H \"Accept-Encoding: gzip, deflate\""))
        XCTAssertTrue(curl.contains("-d \"{\\\"name\\\":\\\"John Doe\\\",\\\"age\\\":30}\""))
        XCTAssertTrue(curl.contains("https://api.example.com/users/123?include=profile"))
    }

    // MARK: - Sensitive Data Redaction Tests

    func testGenerateCurlRedactsSensitiveHeadersByDefault() async {
        let request = TestDebugRequest(debugType: .request)
        var urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)
        urlRequest.setValue("Bearer secret-token", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("api-key-secret", forHTTPHeaderField: "X-API-Key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let curl = await request.generateCurl(urlRequest: urlRequest)

        XCTAssertTrue(curl.contains("-H \"Authorization: <redacted>\""))
        XCTAssertTrue(curl.contains("-H \"X-API-Key: <redacted>\""))
        XCTAssertTrue(curl.contains("-H \"Content-Type: application/json\""))
        XCTAssertFalse(curl.contains("secret-token"))
        XCTAssertFalse(curl.contains("api-key-secret"))
    }

    func testGenerateCurlShowsSensitiveHeadersWhenEnabled() async {
        await Harbor.setLogSensitiveHeaders(true)

        let request = TestDebugRequest(debugType: .request)
        var urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)
        urlRequest.setValue("Bearer secret-token", forHTTPHeaderField: "Authorization")

        let curl = await request.generateCurl(urlRequest: urlRequest)

        XCTAssertTrue(curl.contains("-H \"Authorization: Bearer secret-token\""))
    }

    func testGenerateCurlRedactsHeaderNamesCaseInsensitively() async {
        let request = TestDebugRequest(debugType: .request)
        var urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)
        urlRequest.setValue("api-key-secret", forHTTPHeaderField: "x-api-key")

        let curl = await request.generateCurl(urlRequest: urlRequest)

        XCTAssertFalse(curl.contains("api-key-secret"))
    }

    func testGenerateCurlRedactsCookies() async {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = true
        let cookieStorage = HTTPCookieStorage.shared
        configuration.httpCookieStorage = cookieStorage
        let cookie = HTTPCookie(properties: [
            .domain: "api.example.com",
            .path: "/",
            .name: "session",
            .value: "super-secret-cookie",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(3600)
        ])!
        cookieStorage.setCookie(cookie)
        addTeardownBlock { cookieStorage.deleteCookie(cookie) }
        await Harbor.setCustomURLSession(URLSession(configuration: configuration))

        let request = TestDebugRequest(debugType: .request)
        let urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)

        let curl = await request.generateCurl(urlRequest: urlRequest)

        XCTAssertTrue(curl.contains("-b \"<redacted>\""))
        XCTAssertFalse(curl.contains("super-secret-cookie"))
    }

    func testGenerateCurlShowsCookiesWhenSensitiveLoggingEnabled() async {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = true
        let cookieStorage = HTTPCookieStorage.shared
        configuration.httpCookieStorage = cookieStorage
        let cookie = HTTPCookie(properties: [
            .domain: "api.example.com",
            .path: "/",
            .name: "session",
            .value: "super-secret-cookie",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(3600)
        ])!
        cookieStorage.setCookie(cookie)
        addTeardownBlock { cookieStorage.deleteCookie(cookie) }
        await Harbor.setCustomURLSession(URLSession(configuration: configuration))
        await Harbor.setLogSensitiveHeaders(true)

        let request = TestDebugRequest(debugType: .request)
        let urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)

        let curl = await request.generateCurl(urlRequest: urlRequest)

        XCTAssertTrue(curl.contains("session=super-secret-cookie"))
    }

    func testGenerateCurlDoesNotLeakSharedSessionCookies() async {
        // Given: a session cookie stored in URLSession.shared (not Harbor's session)
        let sharedCookie = HTTPCookie(properties: [
            .domain: "api.example.com",
            .path: "/",
            .name: "shared",
            .value: "shared-secret",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(3600)
        ])!
        HTTPCookieStorage.shared.setCookie(sharedCookie)
        addTeardownBlock { HTTPCookieStorage.shared.deleteCookie(sharedCookie) }

        // And: Harbor configured with a custom session with an empty cookie storage
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = HTTPCookieStorage()
        await Harbor.setCustomURLSession(URLSession(configuration: configuration))

        let request = TestDebugRequest(debugType: .request)
        let urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)

        // When
        let curl = await request.generateCurl(urlRequest: urlRequest)

        // Then: cookies from URLSession.shared must not appear in the cURL
        XCTAssertFalse(curl.contains("shared-secret"))
        XCTAssertFalse(curl.contains("-b \""))
    }

    func testGenerateCurlUsesCurrentSessionAdditionalHeaders() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["X-Custom-Header": "custom-value", "X-API-Key": "session-api-key"]
        await Harbor.setCustomURLSession(URLSession(configuration: configuration))

        let request = TestDebugRequest(debugType: .request)
        let urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)

        let curl = await request.generateCurl(urlRequest: urlRequest)

        XCTAssertTrue(curl.contains("-H \"X-Custom-Header: custom-value\""))
        // Sensitive headers coming from the session configuration are redacted too
        XCTAssertTrue(curl.contains("-H \"X-API-Key: <redacted>\""))
        XCTAssertFalse(curl.contains("session-api-key"))
    }

    func testRedactedHeadersUsedInStructuredLog() async {
        let request = TestDebugRequest(debugType: .request)
        let headers = [
            "Authorization": "Bearer secret-token",
            "X-API-Key": "api-key-secret",
            "Content-Type": "application/json"
        ]

        let redacted = await request.redactedHeaders(headers)
        let redactedNil = await request.redactedHeaders(nil)

        XCTAssertEqual(redacted?["Authorization"], "<redacted>")
        XCTAssertEqual(redacted?["X-API-Key"], "<redacted>")
        XCTAssertEqual(redacted?["Content-Type"], "application/json")
        XCTAssertNil(redactedNil)
    }
    
    // MARK: - Debug Request Integration Tests
    
    func testDebugRequestWithMock() async {
        let testData = MockModel(quote: "Debug Test Quote")
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = await HMock(request: TestDebugRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestDebugRequest(debugType: .requestAndResponse)
        
        let response = await request.request()
        switch response {
        case .success(let data):
            XCTAssertEqual(data.quote, "Debug Test Quote")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    func testDebugRequestWithErrorResponse() async {
        let mock = await HMock(request: TestDebugRequest.self, statusCode: 404, jsonResponse: nil)
        await Harbor.register(mock: mock)
        
        let request = TestDebugRequest(debugType: .requestAndResponse)
        
        let response = await request.request()
        switch response {
        case .success(_):
            XCTFail("Expected error but got success")
        case .error(let error):
            XCTAssertNotNil(error, "Should receive an error response")
        }
    }
    
    // MARK: - Dictionary to JSON Tests
    
    func testDictionaryToJSONStringValidDictionary() async {
        let request = TestDebugRequest(debugType: .request)
        let dictionary = ["key1": "value1", "key2": "value2"]
        
        let jsonString = await request.dictionaryToJSONString(dictionary)
        
        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString!.contains("key1"))
        XCTAssertTrue(jsonString!.contains("value1"))
        XCTAssertTrue(jsonString!.contains("key2"))
        XCTAssertTrue(jsonString!.contains("value2"))
    }
    
    func testDictionaryToJSONStringEmptyDictionary() async {
        let request = TestDebugRequest(debugType: .request)
        let dictionary: [String: Any] = [:]
        
        let jsonString = await request.dictionaryToJSONString(dictionary)
        
        XCTAssertNil(jsonString)
    }
    
    func testDictionaryToJSONStringNilDictionary() async {
        let request = TestDebugRequest(debugType: .request)
        
        let jsonString = await request.dictionaryToJSONString(nil)
        
        XCTAssertNil(jsonString)
    }
    
    // MARK: - Print Methods Tests (Behavioral)
    
    func testPrintRequestWithRequestDebugType() async {
        let request = TestDebugRequest(debugType: .request)
        let urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)
        
        // This test verifies that the method doesn't crash when called
        // The actual logging is handled by LogBird and would require more complex mocking
        await XCTAssertNoThrowAsync(await request.logRequest(urlRequest: urlRequest))
    }
    
    func testPrintRequestWithNoneDebugType() async {
        let request = TestDebugRequest(debugType: .none)
        let urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)
        
        // Should not crash even with .none debug type
        await XCTAssertNoThrowAsync(await request.logRequest(urlRequest: urlRequest))
    }
    
    func testPrintResponseWithResponseDebugType() async {
        let request = TestDebugRequest(debugType: .response)
        let response = HTTPURLResponse(url: URL(string: "https://api.example.com/test")!, 
                                      statusCode: 200, 
                                      httpVersion: nil, 
                                      headerFields: nil)!
        let data = "test response".data(using: .utf8)!
        
        await XCTAssertNoThrowAsync(await request.logResponse(httpResponse: response, data: data, duration: 123.45))
    }
    
    func testPrintErrorResponseWithError() async {
        let request = TestDebugRequest(debugType: .requestAndResponse)
        let error = HRequestError.noConnection
        
        await XCTAssertNoThrowAsync(await request.logErrorResponse(error: error))
    }
}

// MARK: - Test Models and Requests

private struct TestDebugRequest: HGetRequestProtocol, HDebugRequestProtocol {
    typealias Model = MockModel
    
    let url: String = "https://api.example.com/test"
    var debugType: HDebugRequestType
    
    init(debugType: HDebugRequestType) {
        self.debugType = debugType
    }
}
