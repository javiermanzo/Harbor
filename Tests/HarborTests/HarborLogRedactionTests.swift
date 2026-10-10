//
//  HarborLogRedactionTests.swift
//  HarborTests
//
//  The single redaction policy applied to debug logs, generated cURL commands and
//  `HRequestError.api` descriptions; crash-safety of body serialization; and the logging
//  switch reaching the underlying LogBird loggers.
//

import XCTest
import LogBird
@testable import Harbor

/// POST request with debug logging and arbitrary body parameters.
private struct DebugPostRequest: HPostRequestProtocol, HDebugRequestProtocol, @unchecked Sendable {
    var url: String = "https://api.example.com/login"
    var headerParameters: [String: String]?
    var bodyParameters: [String: Any]?
    var multipartBody: [String: HFormValue]?
}

/// GET request with debug logging and query parameters.
private struct DebugQueryRequest: HGetRequestProtocol, HDebugRequestProtocol {
    typealias Model = MockModel
    var url: String = "https://api.example.com/search"
    var queryParameters: [String: String]?
}

private struct NotJSONEncodable {
    let value = 1
}

final class HarborLogRedactionTests: XCTestCase {

    override func setUp() async throws {
        await Harbor.setLogSensitiveValues(false)
        await Harbor.setLoggingEnabled(true)
        await Harbor.updateLogSensitiveKeys(.reset)
        await HLogger.logger.clearLogs()
    }

    override func tearDown() async throws {
        await Harbor.setLogSensitiveValues(false)
        await Harbor.setLoggingEnabled(true)
        await Harbor.updateLogSensitiveKeys(.reset)
        await HLogger.logger.clearLogs()
    }

    // MARK: - Helpers

    /// The last log entry recorded by Harbor's debug logger.
    private func lastLog() async throws -> LBLog {
        let last = await HLogger.logger.logs.last
        return try XCTUnwrap(last, "Expected a log entry")
    }

    private func info(_ log: LBLog, _ key: String) -> String? {
        log.additionalInfo?[key]?.description
    }

    private func extra(_ log: LBLog, _ key: String) -> String? {
        log.extraMessages?.first(where: { $0.key == key })?.value
    }

    // MARK: - Request Body Parameters

    func testLoggedBodyParametersRedactSensitiveFields() async throws {
        let request = DebugPostRequest(bodyParameters: ["username": "johndoe", "password": "hunter2", "nested": ["client_secret": "cs-1", "plan": "pro"]])
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)

        await request.logRequest(urlRequest: urlRequest)

        let log = try await lastLog()
        let body = try XCTUnwrap(info(log, "bodyParameters"))
        XCTAssertFalse(body.contains("hunter2"), "password must not leak in logged body parameters")
        XCTAssertFalse(body.contains("cs-1"), "nested client_secret must not leak")
        XCTAssertTrue(body.contains("johndoe"))
        XCTAssertTrue(body.contains("pro"))

        let curl = try XCTUnwrap(extra(log, "cURL"))
        XCTAssertFalse(curl.contains("hunter2"), "password must not leak in the cURL body")
        XCTAssertFalse(curl.contains("cs-1"))
        XCTAssertTrue(curl.contains("johndoe"))
    }

    // MARK: - Headers

    func testCustomSessionHeaderIsRedactedByDefault() async throws {
        let request = DebugPostRequest(headerParameters: ["X-Session-Id": "sess-42", "X-Trace": "trace-1"], bodyParameters: ["a": 1])
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)

        await request.logRequest(urlRequest: urlRequest)

        let log = try await lastLog()
        let headers = try XCTUnwrap(info(log, "headerParameters"))
        let curl = try XCTUnwrap(extra(log, "cURL"))
        XCTAssertFalse(headers.contains("sess-42"))
        XCTAssertFalse(curl.contains("sess-42"))
        XCTAssertTrue(headers.contains("trace-1"))
        XCTAssertTrue(curl.contains("-H \"X-Trace: trace-1\""))
    }

    func testConfiguredSensitiveKeysApplyToHeadersAndBodies() async throws {
        await Harbor.updateLogSensitiveKeys(.add(["otp"]))
        let request = DebugPostRequest(headerParameters: ["X-OTP": "123456"], bodyParameters: ["otp": "654321", "name": "visible"])
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)

        await request.logRequest(urlRequest: urlRequest)

        let log = try await lastLog()
        let rendered = [info(log, "headerParameters"), info(log, "bodyParameters"), extra(log, "cURL")].compactMap { $0 }.joined()
        XCTAssertFalse(rendered.contains("123456"))
        XCTAssertFalse(rendered.contains("654321"))
        XCTAssertTrue(rendered.contains("visible"))
    }

    func testAuthProviderHeaderKeyIsRedactedEvenWithANonStandardName() async throws {
        let request = DebugPostRequest(bodyParameters: ["a": 1])
        let authHeader = HAuthorizationHeader(key: "X-Harbor-Opaque", value: "opaque-credential-value")
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request, authHeader: authHeader)

        let curl = await request.generateCurl(urlRequest: urlRequest)
        let headers = await request.redactedHeaders(urlRequest.allHTTPHeaderFields)

        XCTAssertFalse(curl.contains("opaque-credential-value"))
        XCTAssertEqual(headers?["X-Harbor-Opaque"], "<redacted>")
    }

    // MARK: - Query Values

    func testSensitiveQueryValuesAreRedactedInLoggedURLAndCurl() async throws {
        let request = DebugQueryRequest(queryParameters: ["api_key": "k-123", "page": "2"])
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
        XCTAssertTrue(urlRequest.url?.absoluteString.contains("k-123") == true, "The real request keeps the value")

        await request.logRequest(urlRequest: urlRequest)

        let log = try await lastLog()
        let url = try XCTUnwrap(info(log, "url"))
        let query = try XCTUnwrap(info(log, "queryParameters"))
        let curl = try XCTUnwrap(extra(log, "cURL"))
        for rendered in [url, query, curl] {
            XCTAssertFalse(rendered.contains("k-123"), "api_key must not leak: \(rendered)")
            XCTAssertTrue(rendered.contains("2"))
        }
        XCTAssertTrue(url.contains("api_key=<redacted>"))
        XCTAssertTrue(url.contains("page=2"))
    }

    func testRedactedURLStringKeepsFragmentAndNonSensitiveItems() {
        let url = URL(string: "https://api.example.com/x?token=abc&q=swift#top")!
        let redacted = HRedactionPolicy(isEnabled: true).redactedURLString(url)
        XCTAssertEqual(redacted, "https://api.example.com/x?token=<redacted>&q=swift#top")
    }

    // MARK: - Response Headers

    func testLogResponseRedactsSetCookieHeader() async throws {
        let request = TestDebugRequest(debugType: .response)
        let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://api.example.com/login")!, statusCode: 200, httpVersion: nil,
                                                     headerFields: ["Set-Cookie": "session=cookie-secret; HttpOnly", "Content-Type": "application/json"]))

        await request.logResponse(httpResponse: response, data: Data("{}".utf8), duration: 1)

        let log = try await lastLog()
        let headers = try XCTUnwrap(extra(log, "Response Headers"))
        XCTAssertFalse(headers.contains("cookie-secret"))
        XCTAssertTrue(headers.contains("application/json"))
        XCTAssertNil(extra(log, "Response Object"), "The raw HTTPURLResponse description must not be logged")
        for entry in log.extraMessages ?? [] {
            XCTAssertFalse(entry.value.contains("cookie-secret"), "\(entry.key) leaks Set-Cookie")
        }
    }

    // MARK: - Opt-out

    func testLogSensitiveHeadersShowsEverything() async throws {
        await Harbor.setLogSensitiveValues(true)
        let request = DebugPostRequest(headerParameters: ["X-Session-Id": "sess-42"], bodyParameters: ["password": "hunter2"])
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)

        await request.logRequest(urlRequest: urlRequest)

        let log = try await lastLog()
        XCTAssertTrue(info(log, "bodyParameters")?.contains("hunter2") == true)
        XCTAssertTrue(extra(log, "cURL")?.contains("hunter2") == true)
        XCTAssertTrue(extra(log, "cURL")?.contains("sess-42") == true)

        let queryRequest = DebugQueryRequest(queryParameters: ["api_key": "k-123"])
        let queryURLRequest = try await HURLBuilder.buildUrlRequest(request: queryRequest)
        let curl = await queryRequest.generateCurl(urlRequest: queryURLRequest)
        XCTAssertTrue(curl.contains("k-123"))

        let error = HRequestError.api(statusCode: 401, data: Data(#"{"access_token":"tok-1"}"#.utf8))
        XCTAssertTrue(error.errorDescription?.contains("tok-1") == true)
    }

    // MARK: - Multipart in cURL

    func testCurlOmitsMultipartBodyWhileRedacting() async throws {
        let request = DebugPostRequest(multipartBody: ["password": .text("hunter2")])
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)

        let curl = await request.generateCurl(urlRequest: urlRequest)

        XCTAssertFalse(curl.contains("hunter2"))
        XCTAssertTrue(curl.contains("multipart body"))
    }

    // MARK: - HRequestError.api Description

    func testAPIErrorDescriptionRedactsJSONBody() {
        let body = #"{"access_token":"tok-1","refresh_token":"tok-2","error":"invalid_grant"}"#
        let description = HRequestError.api(statusCode: 400, data: Data(body.utf8)).errorDescription ?? ""

        XCTAssertFalse(description.contains("tok-1"))
        XCTAssertFalse(description.contains("tok-2"))
        XCTAssertTrue(description.contains("invalid_grant"))
        XCTAssertTrue(description.contains("<redacted>"))
    }

    func testAPIErrorDescriptionOmitsUnparseableJSON() {
        // Truncated JSON cannot be parsed, so its sensitive values cannot be located.
        let body = #"{"access_token":"tok-1","user":"#
        let description = HRequestError.api(statusCode: 500, data: Data(body.utf8)).errorDescription ?? ""

        XCTAssertFalse(description.contains("tok-1"))
        XCTAssertTrue(description.contains("omitted"))
    }

    func testAPIErrorDescriptionRedactsFormEncodedBody() {
        let body = "access_token=tok-1&token_type=bearer&scope=read"
        let description = HRequestError.api(statusCode: 400, data: Data(body.utf8)).errorDescription ?? ""

        XCTAssertFalse(description.contains("tok-1"))
        XCTAssertTrue(description.contains("scope=read"))
    }

    func testAPIErrorDescriptionKeepsPlainTextPrefix() {
        let description = HRequestError.api(statusCode: 503, data: Data("Service Unavailable".utf8)).errorDescription ?? ""
        XCTAssertTrue(description.contains("Service Unavailable"))
    }

    // MARK: - F10: Non-JSON Values Never Crash

    /// Values `JSONSerialization` cannot represent; handing them to it raises an
    /// uncatchable Objective-C exception that would kill the test process.
    private var unserializableValues: [String: Any] {
        ["date": Date(), "data": Data([1, 2]), "nan": Double.nan, "infinity": Double.infinity, "custom": NotJSONEncodable()]
    }

    func testJSONBodyWithUnserializableValuesThrowsMalformedRequest() async {
        for (key, value) in unserializableValues {
            let request = DebugPostRequest(bodyParameters: ["ok": "fine", key: value])
            do {
                _ = try await HURLBuilder.buildUrlRequest(request: request)
                XCTFail("Expected malformedRequest for \(key)")
            } catch HRequestError.malformedRequest(let reason) {
                XCTAssertTrue(reason?.contains(key) == true, "The reason should name the field: \(reason ?? "nil")")
            } catch {
                XCTFail("Expected malformedRequest for \(key) but got \(error)")
            }
        }
    }

    func testDataBodyRejectsUnserializableValues() {
        XCTAssertThrowsError(try HURLBuilder.jsonBody(params: ["value": Double.nan])) { error in
            guard case HRequestError.malformedRequest = error else {
                return XCTFail("Expected malformedRequest but got: \(error)")
            }
        }
    }

    func testDictionaryToJSONStringReturnsPlaceholderForUnserializableValues() async throws {
        let request = TestDebugRequest(debugType: .request)
        for (key, value) in unserializableValues {
            let json = await request.dictionaryToJSONString(["ok": "fine", key: value])
            let placeholder = try XCTUnwrap(json)
            XCTAssertTrue(placeholder.hasPrefix("<not JSON-serializable"), placeholder)
            XCTAssertTrue(placeholder.contains(key))
        }
    }

    func testLoggingBodyParametersWithNonFiniteNumbersDoesNotCrash() async throws {
        // Body parameters JSON cannot represent must not crash the debug log.
        let request = DebugPostRequest(bodyParameters: ["nan": Double.nan, "inf": Double.infinity, "date": Date()])
        let urlRequest = URLRequest(url: try XCTUnwrap(URL(string: request.url)))

        await request.logRequest(urlRequest: urlRequest)

        let log = try await lastLog()
        XCTAssertTrue(info(log, "bodyParameters")?.contains("not JSON-serializable") == true)
    }

    // MARK: - F19: Logging Switch

    func testSetLoggingEnabledTogglesTheLogBirdLoggers() async {
        await Harbor.setLoggingEnabled(false)
        var states = await [HLogger.logger.isEnabled, HURLSessionDelegate.logger.isEnabled, PKCS12.logger.isEnabled]
        XCTAssertEqual(states, [false, false, false])

        await Harbor.setLoggingEnabled(true)
        states = await [HLogger.logger.isEnabled, HURLSessionDelegate.logger.isEnabled, PKCS12.logger.isEnabled]
        XCTAssertEqual(states, [true, true, true])
    }

    func testSetLoggingEnabledRecordsWhenLogBirdStartsDisabled() async {
        // Given the release-build default: LogBird's recording switch off
        await Harbor.setLoggingEnabled(false)
        let isEnabled = await HLogger.logger.isEnabled
        XCTAssertFalse(isEnabled)

        // When logging is enabled through Harbor
        await Harbor.setLoggingEnabled(true)
        await HLogger.log("recorded in release", level: .info)

        // Then the entry is recorded
        let messages = await HLogger.logger.logs.compactMap(\.message)
        XCTAssertTrue(messages.contains("recorded in release"))
    }

    func testSecurityWarningsAreRecordedWithLoggingDisabled() async {
        await Harbor.setLoggingEnabled(false)
        await HLogger.securityLogger.clearLogs()

        await HLogger.securityWarning("pinning not enforced")

        let securityLogs = await HLogger.securityLogger.logs
        XCTAssertEqual(securityLogs.last?.message, "pinning not enforced")
        XCTAssertEqual(securityLogs.last?.level, .warning)
        await HLogger.securityLogger.clearLogs()
    }
}
