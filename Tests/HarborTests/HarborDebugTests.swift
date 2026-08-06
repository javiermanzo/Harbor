//
//  HarborDebugTests.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import XCTest
@testable import Harbor

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
        XCTAssertTrue(curl.contains(#"-d '{"key":"value"}'"#))
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

    func testGenerateCurlEscapesShellSpecialsInHeaderValue() async {
        let request = TestDebugRequest(debugType: .request)
        var urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)
        urlRequest.setValue("va\"l$ue\\`tick`", forHTTPHeaderField: "X-Test")

        let curl = await request.generateCurl(urlRequest: urlRequest)

        XCTAssertTrue(curl.contains("-H \"X-Test: va\\\"l\\$ue\\\\\\`tick\\`\""))
    }

    func testGenerateCurlSingleQuotesAndEscapesBody() async {
        let request = TestDebugRequest(debugType: .request)
        var urlRequest = URLRequest(url: URL(string: "https://api.example.com/test")!)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = #"{"msg":"it's $HOME `x`"}"#.data(using: .utf8)!

        let curl = await request.generateCurl(urlRequest: urlRequest)

        // Single-quoted body: only the embedded single quote is escaped ('\'').
        XCTAssertTrue(curl.contains(#"-d '{"msg":"it'\''s $HOME `x`"}'"#))
    }

    func testGenerateCurlEscapesShellSpecialsInURL() async {
        let request = TestDebugRequest(debugType: .request)
        let urlRequest = URLRequest(url: URL(string: "https://api.example.com/test?price=$100")!)

        let curl = await request.generateCurl(urlRequest: urlRequest)

        XCTAssertTrue(curl.contains("\"https://api.example.com/test?price=\\$100\""))
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
        XCTAssertTrue(curl.contains(#"-d '{"name":"John Doe","age":30}'"#))
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

        let mock = HMock(request: TestDebugRequest.self, statusCode: 200, jsonResponse: jsonString)
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
        let mock = HMock(request: TestDebugRequest.self, statusCode: 404, jsonResponse: nil)
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

    func testDictionaryToJSONStringSortsKeys() async {
        let request = TestDebugRequest(debugType: .request)
        let dictionary: [String: Any] = ["zebra": 1, "apple": 2, "mango": 3]

        let jsonString = await request.dictionaryToJSONString(dictionary)

        XCTAssertEqual(jsonString, #"{"apple":2,"mango":3,"zebra":1}"#)
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

    // MARK: - logErrorResponse is not filtered by debugType

    func testLogErrorResponseLogsEvenForNoneDebugType() async {
        await Harbor.setLoggingEnabled(true)
        await HLogger.logger.clearLogs()
        addTeardownBlock { await HLogger.logger.clearLogs() }

        let request = TestDebugRequest(debugType: .none)
        await request.logErrorResponse(error: .noConnection)

        let logs = await HLogger.logger.logs
        guard let last = logs.last else {
            XCTFail("Expected an error log regardless of debugType")
            return
        }
        XCTAssertTrue(last.message?.contains("Response Error") == true)
        XCTAssertEqual(last.level, .error)
    }

    // MARK: - Response body redaction

    func testLogResponseRedactsSensitiveJSONBody() async {
        await Harbor.setLogSensitiveHeaders(false)
        await Harbor.setLoggingEnabled(true)
        await HLogger.logger.clearLogs()
        addTeardownBlock { await HLogger.logger.clearLogs() }

        let body = #"{"access_token":"abc123","refresh_token":"def456","user":"johndoe"}"#
        let data = body.data(using: .utf8)!
        let response = HTTPURLResponse(url: URL(string: "https://api.example.com/login")!,
                                       statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!

        let request = TestDebugRequest(debugType: .response)
        await request.logResponse(httpResponse: response, data: data, duration: 12.0)

        guard let last = await HLogger.logger.logs.last,
              let responseValue = last.extraMessages?.first(where: { $0.key == "Response Value" })?.value else {
            XCTFail("Expected a Response Value extra message")
            return
        }

        XCTAssertTrue(responseValue.contains("<redacted>"), "Sensitive fields should be redacted")
        XCTAssertFalse(responseValue.contains("abc123"), "access_token value must not leak")
        XCTAssertFalse(responseValue.contains("def456"), "refresh_token value must not leak")
        XCTAssertTrue(responseValue.contains("johndoe"), "Non-sensitive fields should be preserved")
    }

    func testLogResponseDoesNotRedactBodyWhenSensitiveHeadersEnabled() async {
        await Harbor.setLogSensitiveHeaders(true)
        await Harbor.setLoggingEnabled(true)
        await HLogger.logger.clearLogs()
        addTeardownBlock {
            await Harbor.setLogSensitiveHeaders(false)
            await HLogger.logger.clearLogs()
        }

        let body = #"{"access_token":"abc123"}"#
        let data = body.data(using: .utf8)!
        let response = HTTPURLResponse(url: URL(string: "https://api.example.com/login")!,
                                       statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!

        let request = TestDebugRequest(debugType: .response)
        await request.logResponse(httpResponse: response, data: data, duration: 12.0)

        guard let responseValue = await HLogger.logger.logs.last?
            .extraMessages?.first(where: { $0.key == "Response Value" })?.value else {
            XCTFail("Expected a Response Value extra message")
            return
        }
        XCTAssertTrue(responseValue.contains("abc123"), "Raw token should be visible when opt-in is on")
    }

    func testRedactedResponseBodyLeavesNonJSONUnchanged() async {
        await Harbor.setLogSensitiveHeaders(false)
        let request = TestDebugRequest(debugType: .response)
        let body = "plain-body-without-tokens"
        let data = body.data(using: .utf8)!
        let response = HTTPURLResponse(url: URL(string: "https://api.example.com/")!,
                                       statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/plain"])!

        let result = await request.redactedResponseBody(data: data, httpResponse: response)
        XCTAssertEqual(result, body)
    }

    func testLogResponseRedactsNestedSensitiveJSONBody() async {
        await Harbor.setLogSensitiveHeaders(false)
        await Harbor.setLoggingEnabled(true)
        await HLogger.logger.clearLogs()
        addTeardownBlock { await HLogger.logger.clearLogs() }

        let body = #"{"access_token":"secret-value","user":{"refresh_token":"x-refresh","name":"johndoe"}}"#
        let data = body.data(using: .utf8)!
        let response = HTTPURLResponse(url: URL(string: "https://api.example.com/login")!,
                                       statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!

        let request = TestDebugRequest(debugType: .response)
        await request.logResponse(httpResponse: response, data: data, duration: 12.0)

        guard let responseValue = await HLogger.logger.logs.last?
            .extraMessages?.first(where: { $0.key == "Response Value" })?.value else {
            XCTFail("Expected a Response Value extra message")
            return
        }

        XCTAssertFalse(responseValue.contains("secret-value"), "access_token value must not leak")
        XCTAssertFalse(responseValue.contains("x-refresh"), "nested refresh_token value must not leak")
        XCTAssertTrue(responseValue.contains("\"access_token\":\"<redacted>\""))
        XCTAssertTrue(responseValue.contains("\"refresh_token\":\"<redacted>\""))
        XCTAssertTrue(responseValue.contains("\"name\":\"johndoe\""), "Non-sensitive fields should be preserved")
    }

    func testRedactedResponseBodyReturnsBinaryPlaceholderForNonUTF8() async {
        let request = TestDebugRequest(debugType: .response)
        let data = Data([0xFF, 0xFE, 0xFD, 0x80])
        let response = HTTPURLResponse(url: URL(string: "https://api.example.com/image")!,
                                       statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/octet-stream"])!

        let result = await request.redactedResponseBody(data: data, httpResponse: response)

        XCTAssertEqual(result, "<binary 4 bytes>")
    }

    func testRedactedResponseBodyTruncatesLargeBodies() async {
        await Harbor.setLogSensitiveHeaders(false)
        let request = TestDebugRequest(debugType: .response)
        let body = String(repeating: "a", count: 20 * 1024)
        let data = body.data(using: .utf8)!
        let response = HTTPURLResponse(url: URL(string: "https://api.example.com/")!,
                                       statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/plain"])!

        let result = await request.redactedResponseBody(data: data, httpResponse: response)

        let marker = "… <truncated>"
        XCTAssertEqual(result?.count, 16 * 1024 + marker.count)
        XCTAssertTrue(result?.hasSuffix(marker) == true)
    }
}

// MARK: - Test Models and Requests

