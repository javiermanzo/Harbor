//
//  HarborJRPCHardeningTests.swift
//  HarborJRPC
//
//  Covers identifier decoding, logging, header/retry merging, HTTP error envelopes,
//  lossless numbers and notification/batch delivery of the JSON-RPC module.
//

import XCTest
@testable import Harbor
@testable import HarborJRPC

/// URLProtocol stub injected through `HConfig.protocolClasses`. It answers with a scripted
/// sequence of responses (repeating the last one) and records every request it sees.
private final class JRPCStubProtocol: URLProtocol {
    struct Response {
        let statusCode: Int
        let body: String
    }

    struct Recorded {
        let url: URL?
        let headers: [String: String]
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _responses: [Response] = [Response(statusCode: 200, body: "")]
    nonisolated(unsafe) private static var _recorded: [Recorded] = []

    static var recorded: [Recorded] {
        lock.lock()
        defer { lock.unlock() }
        return _recorded
    }

    static func respond(_ responses: Response...) {
        lock.lock()
        _responses = responses
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        _responses = [Response(statusCode: 200, body: "")]
        _recorded = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        let host = request.url?.host
        return host == "rpc.example.com" || host == "other.example.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = request.httpBody ?? Self.readBody(from: request.httpBodyStream)

        Self.lock.lock()
        let index = Self._recorded.count
        Self._recorded.append(Recorded(url: request.url, headers: request.allHTTPHeaderFields ?? [:], body: body))
        let response = Self._responses[min(index, Self._responses.count - 1)]
        Self.lock.unlock()

        guard let url = request.url,
              let httpResponse = HTTPURLResponse(url: url, statusCode: response.statusCode, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(from stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@HRequestManagerActor
final class HarborJRPCHardeningTests: XCTestCase {
    private var previousCustomURLSession: URLSession?

    override func setUp() async throws {
        previousCustomURLSession = HConfig.shared.customURLSession
        Harbor.removeAllMocks()
        Harbor.setMocksOnlyInDebug(false)
        // Stubbing relies on Harbor's internally built session; another suite may have left a custom one.
        HConfig.shared.customURLSession = nil
        Harbor.setProtocolClasses([JRPCStubProtocol.self])
        JRPCStubProtocol.reset()
        HarborJRPC.configure(url: URL(string: "https://rpc.example.com/rpc")!, jrpcVersion: "2.0")
    }

    override func tearDown() async throws {
        Harbor.removeAllMocks()
        Harbor.setProtocolClasses(nil)
        HConfig.shared.customURLSession = previousCustomURLSession
        JRPCStubProtocol.reset()
    }

    private func respond(_ statusCode: Int, _ body: String) {
        JRPCStubProtocol.respond(.init(statusCode: statusCode, body: body))
    }

    private func sentJSON(at index: Int = 0) throws -> Any {
        let recorded = JRPCStubProtocol.recorded
        XCTAssertGreaterThan(recorded.count, index)
        return try JSONSerialization.jsonObject(with: recorded[index].body)
    }

    // MARK: - F1 Identifier Decoding

    func testIdentifierDecodingRejectsOutOfRangeAndFractionalNumbers() async throws {
        let decoder = JSONDecoder()

        for literal in ["1e30", "9223372036854775808", "-1e30", "1.5"] {
            XCTAssertThrowsError(try decoder.decode(HJRPCId.self, from: Data(literal.utf8)), "id \(literal) must not decode") { error in
                XCTAssertTrue(error is DecodingError, "Expected DecodingError for \(literal), got \(error)")
            }
        }

        XCTAssertEqual(try decoder.decode(HJRPCId.self, from: Data("42".utf8)), .number(42))
        XCTAssertEqual(try decoder.decode(HJRPCId.self, from: Data("1.0".utf8)), .number(1))
        XCTAssertEqual(try decoder.decode(HJRPCId.self, from: Data("9223372036854775807".utf8)), .number(Int.max))
    }

    func testResponseWithOutOfRangeIdentifierFailsInsteadOfTrapping() async throws {
        // Given: a response whose id cannot be represented as an Int.
        respond(200, #"{"jsonrpc":"2.0","id":1e30,"result":"0x1"}"#)

        // When
        let response = await StringRequest(method: "eth_blockNumber", requestID: .number(1)).requestResult()

        // Then
        guard case .error(.codable) = response else {
            return XCTFail("Expected a decoding error but got: \(response)")
        }
    }

    // MARK: - F12 Logging

    func testWrapperCarriesTheDebugTypeOfRequestsThatOptIn() async throws {
        let debugRequest = DebugStringRequest(method: "eth_chainId", debugType: .response)
        let plainRequest = StringRequest(method: "eth_chainId")

        XCTAssertEqual(try debugRequest.wrapRequest(type: String.self).requestedDebugType, .response)
        XCTAssertNil(try plainRequest.wrapRequest(type: String.self).requestedDebugType)
    }

    func testDebugRequestConformsToHDebugRequestProtocolAndForwardsTheWrapper() async throws {
        let wrapper = try DebugStringRequest(method: "eth_chainId", debugType: .request, headers: ["X-Trace": "1"]).wrapRequest(type: String.self)
        let debugRequest = HJRPCDebugRequest(base: wrapper, debugType: .request)

        let debuggable = try XCTUnwrap((debugRequest as Any) as? HDebugRequestProtocol)
        XCTAssertEqual(debuggable.debugType, .request)
        XCTAssertEqual(debugRequest.url, wrapper.url)
        XCTAssertEqual(debugRequest.rawBody, wrapper.rawBody)
        XCTAssertEqual(debugRequest.headerParameters, ["X-Trace": "1"])
        XCTAssertFalse((wrapper as Any) is HDebugRequestProtocol, "Requests that do not opt in must not be logged")
    }

    func testDebugRequestIsSentThroughHarbor() async throws {
        // Given
        respond(200, #"{"jsonrpc":"2.0","id":"1","result":"0x1"}"#)

        // When
        let result = try await DebugStringRequest(method: "eth_chainId", debugType: .requestAndResponse, requestID: .string("1")).request()

        // Then
        XCTAssertEqual(result, "0x1")
        XCTAssertEqual(JRPCStubProtocol.recorded.count, 1)
    }

    func testBatchDebugTypeIsTheMostVerboseRequested() async {
        XCTAssertNil(HJRPCRequestManager.batchDebugType(for: [StringRequest(method: "a"), StringRequest(method: "b")]))
        XCTAssertEqual(HJRPCRequestManager.batchDebugType(for: [StringRequest(method: "a"), DebugStringRequest(method: "b", debugType: .none)]), HDebugRequestType.none)
        XCTAssertEqual(HJRPCRequestManager.batchDebugType(for: [DebugStringRequest(method: "a", debugType: .request)]), .request)
        XCTAssertEqual(HJRPCRequestManager.batchDebugType(for: [
            DebugStringRequest(method: "a", debugType: .request),
            DebugStringRequest(method: "b", debugType: .response),
        ]), .requestAndResponse)
        XCTAssertEqual(HJRPCRequestManager.batchDebugType(for: [
            DebugStringRequest(method: "a", debugType: .none),
            DebugStringRequest(method: "b", debugType: .requestAndResponse),
        ]), .requestAndResponse)
    }

    // MARK: - F12 Headers

    func testSingleRequestSendsItsHeaders() async throws {
        respond(200, #"{"jsonrpc":"2.0","id":"1","result":"0x1"}"#)

        _ = try await StringRequest(method: "eth_chainId", requestID: .string("1"), headers: ["X-Api-Key": "abc"]).request()

        XCTAssertEqual(JRPCStubProtocol.recorded.first?.headers["X-Api-Key"], "abc")
    }

    func testBatchMergesHeadersAndTheFirstRequestWins() async throws {
        // Given
        respond(200, #"[{"jsonrpc":"2.0","id":"1","result":"0x1"},{"jsonrpc":"2.0","id":"2","result":"0x2"}]"#)
        let requests: [any HJRPCRequestProtocol] = [
            StringRequest(method: "eth_blockNumber", requestID: .string("1"), headers: ["X-Tenant": "first", "X-One": "1"]),
            StringRequest(method: "eth_chainId", requestID: .string("2"), headers: ["x-tenant": "second", "X-Two": "2"]),
        ]

        // When
        let responses = try await HarborJRPC.batch(requests)

        // Then
        XCTAssertEqual(responses.count, 2)
        let headers = try XCTUnwrap(JRPCStubProtocol.recorded.first?.headers)
        XCTAssertEqual(headers["X-Tenant"], "first")
        XCTAssertEqual(headers["X-One"], "1")
        XCTAssertEqual(headers["X-Two"], "2")
        XCTAssertNil(headers["x-tenant"])
    }

    // MARK: - F12 Retry

    func testBatchRetryPolicyIsTheFirstNonNilOneAndOnlyRetriesWritesWhenEveryRequestOptsIn() async throws {
        let optedIn = HRetryPolicy(maxRetries: 2, retryNonIdempotentRequests: true)
        let notOptedIn = HRetryPolicy(maxRetries: 5)

        XCTAssertNil(HJRPCRequestManager.batchRetryPolicy(for: [StringRequest(method: "a")]))

        let allOptIn = try XCTUnwrap(HJRPCRequestManager.batchRetryPolicy(for: [
            StringRequest(method: "a", retryPolicy: optedIn),
            StringRequest(method: "b", retryPolicy: HRetryPolicy(maxRetries: 9, retryNonIdempotentRequests: true)),
        ]))
        XCTAssertEqual(allOptIn.maxRetries, 2)
        XCTAssertTrue(allOptIn.retryNonIdempotentRequests)

        let mixed = try XCTUnwrap(HJRPCRequestManager.batchRetryPolicy(for: [
            StringRequest(method: "a"),
            StringRequest(method: "b", retryPolicy: optedIn),
            StringRequest(method: "c", retryPolicy: notOptedIn),
        ]))
        XCTAssertEqual(mixed.maxRetries, 2)
        XCTAssertFalse(mixed.retryNonIdempotentRequests)
    }

    func testBatchIsRetriedWithTheDerivedPolicy() async throws {
        // Given: a transient 503 followed by a success.
        JRPCStubProtocol.respond(.init(statusCode: 503, body: ""),
                                 .init(statusCode: 200, body: #"[{"jsonrpc":"2.0","id":"1","result":"0x1"}]"#))
        let policy = HRetryPolicy(maxRetries: 1, baseDelay: 0, jitter: 0...0, retryNonIdempotentRequests: true)

        // When
        let responses = try await HarborJRPC.batch([StringRequest(method: "eth_blockNumber", requestID: .string("1"), retryPolicy: policy)])

        // Then
        XCTAssertEqual(JRPCStubProtocol.recorded.count, 2)
        guard case .success(_, .string("0x1"))? = responses.first else {
            return XCTFail("Expected the retried batch to succeed but got: \(responses)")
        }
    }

    func testSingleRequestRetryPolicyIsHonoredAsWritten() async throws {
        let transient = JRPCStubProtocol.Response(statusCode: 503, body: "")
        let success = JRPCStubProtocol.Response(statusCode: 200, body: #"{"jsonrpc":"2.0","id":"1","result":"0x1"}"#)

        // A JSON-RPC call is a POST: without opting in, a 503 is not retried.
        JRPCStubProtocol.respond(transient, success)
        let notRetried = await StringRequest(method: "eth_call", requestID: .string("1"),
                                             retryPolicy: HRetryPolicy(maxRetries: 1, baseDelay: 0, jitter: 0...0)).requestResult()
        guard case .error(.api(503, _)) = notRetried else {
            return XCTFail("Expected api(503) but got: \(notRetried)")
        }
        XCTAssertEqual(JRPCStubProtocol.recorded.count, 1)

        // Opting in retries it.
        JRPCStubProtocol.reset()
        JRPCStubProtocol.respond(transient, success)
        let retried = try await StringRequest(method: "eth_call", requestID: .string("1"),
                                              retryPolicy: HRetryPolicy(maxRetries: 1, baseDelay: 0, jitter: 0...0, retryNonIdempotentRequests: true)).request()
        XCTAssertEqual(retried, "0x1")
        XCTAssertEqual(JRPCStubProtocol.recorded.count, 2)
    }

    // MARK: - F13 JSON-RPC Errors in Non-2xx Responses

    func testNon2xxResponseWithJSONRPCErrorSurfacesAsJRPCError() async throws {
        respond(500, #"{"jsonrpc":"2.0","error":{"code":-32603,"message":"Internal error"},"id":"1"}"#)

        let response = await StringRequest(method: "eth_call", requestID: .string("1")).requestResult()

        guard case .error(.jrpcError(let error)) = response else {
            return XCTFail("Expected jrpcError but got: \(response)")
        }
        XCTAssertEqual(error.code, -32603)
        XCTAssertEqual(error.message, "Internal error")
        XCTAssertEqual(error.httpStatusCode, 500)
    }

    func testNon2xxResponseWithoutJSONRPCErrorStaysAPIError() async throws {
        respond(502, "<html>Bad Gateway</html>")

        let response = await StringRequest(method: "eth_call", requestID: .string("1")).requestResult()

        guard case .error(.api(502, _)) = response else {
            return XCTFail("Expected api(502) but got: \(response)")
        }
    }

    func testJRPCErrorIn2xxResponseHasNoHTTPStatusCode() async throws {
        respond(200, #"{"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"},"id":"1"}"#)

        let response = await StringRequest(method: "eth_foo", requestID: .string("1")).requestResult()

        guard case .error(.jrpcError(let error)) = response else {
            return XCTFail("Expected jrpcError but got: \(response)")
        }
        XCTAssertNil(error.httpStatusCode)
    }

    func testHTTPStatusCodeIsNotEncoded() async throws {
        let error = HJRPCError(code: 1, message: "m", httpStatusCode: 500)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(error), encoding: .utf8))
        XCTAssertFalse(json.contains("httpStatusCode"))
    }

    func testBatchNon2xxWithSingleErrorThrowsJRPCError() async throws {
        respond(400, #"{"jsonrpc":"2.0","error":{"code":-32600,"message":"Invalid Request"},"id":null}"#)

        do {
            _ = try await HarborJRPC.batch([StringRequest(method: "a", requestID: .string("1"))])
            XCTFail("Expected batch to throw")
        } catch HJRPCRequestError.jrpcError(let error) {
            XCTAssertEqual(error.code, -32600)
            XCTAssertEqual(error.httpStatusCode, 400)
        }
    }

    func testBatchNon2xxWithResponseArrayReturnsTheElements() async throws {
        respond(500, #"[{"jsonrpc":"2.0","error":{"code":-32000,"message":"Server error"},"id":"1"}]"#)

        let responses = try await HarborJRPC.batch([StringRequest(method: "a", requestID: .string("1"))])

        guard case .error(.string("1"), .jrpcError(let error))? = responses.first else {
            return XCTFail("Expected an element error but got: \(responses)")
        }
        XCTAssertEqual(error.code, -32000)
        XCTAssertEqual(error.httpStatusCode, 500)
    }

    func testBatch2xxWithSingleErrorObjectThrowsJRPCError() async throws {
        respond(200, #"{"jsonrpc":"2.0","error":{"code":-32700,"message":"Parse error"},"id":null}"#)

        do {
            _ = try await HarborJRPC.batch([StringRequest(method: "a", requestID: .string("1"))])
            XCTFail("Expected batch to throw")
        } catch HJRPCRequestError.jrpcError(let error) {
            XCTAssertEqual(error.code, -32700)
            XCTAssertNil(error.httpStatusCode)
        }
    }

    func testNotificationNon2xxWithJSONRPCErrorThrowsJRPCError() async throws {
        respond(500, #"{"jsonrpc":"2.0","error":{"code":-32603,"message":"Internal error"},"id":null}"#)

        do {
            try await NotificationRequest().notify()
            XCTFail("Expected notify() to throw")
        } catch HJRPCRequestError.jrpcError(let error) {
            XCTAssertEqual(error.httpStatusCode, 500)
        }
    }

    // MARK: - F14 Lossless Numbers

    func testBigIntegersDecodeExactlyAndReEncodeWithTheSameDigits() async throws {
        for literal in ["18446744073709551615", "9223372036854775808", "-9223372036854775809", "123456789012345678901234567890"] {
            let value = try JSONDecoder().decode(HJSONValue.self, from: Data(literal.utf8))
            guard case .decimal = value else {
                return XCTFail("Expected .decimal for \(literal) but got \(value)")
            }
            let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(value), encoding: .utf8))
            XCTAssertEqual(encoded, literal)
        }

        XCTAssertEqual(try JSONDecoder().decode(HJSONValue.self, from: Data("9223372036854775807".utf8)), .int(Int.max))
        XCTAssertEqual(try JSONDecoder().decode(HJSONValue.self, from: Data("42".utf8)), .int(42))
        XCTAssertEqual(try JSONDecoder().decode(HJSONValue.self, from: Data("1.5".utf8)), .double(1.5))
        XCTAssertEqual(try JSONDecoder().decode(HJSONValue.self, from: Data("true".utf8)), .bool(true))
    }

    func testBigIntegerInsideAResultIsExact() async throws {
        respond(200, #"{"jsonrpc":"2.0","id":"1","result":{"balance":18446744073709551615}}"#)

        let result = try await JSONValueRequest(method: "get_balance", requestID: .string("1")).request()

        XCTAssertEqual(result, .object(["balance": .decimal(Decimal(UInt64.max))]))
    }

    func testAnyValueKeepsUnsignedIntegersAboveIntMax() async {
        XCTAssertEqual(HJSONValue(anyValue: NSNumber(value: UInt64.max)), .decimal(Decimal(UInt64.max)))
        XCTAssertEqual(HJSONValue(anyValue: NSNumber(value: UInt64(Int.max))), .int(Int.max))
        XCTAssertEqual(HJSONValue(anyValue: NSNumber(value: UInt8(7))), .int(7))
        XCTAssertEqual(HJSONValue(anyValue: NSDecimalNumber(string: "18446744073709551615")), .decimal(Decimal(UInt64.max)))
        XCTAssertEqual(HJSONValue(anyValue: NSDecimalNumber(string: "12")), .int(12))
        XCTAssertEqual(HJSONValue.decimal(Decimal(UInt64.max)).anyValue as? NSDecimalNumber, NSDecimalNumber(decimal: Decimal(UInt64.max)))
    }

    func testUInt64ParameterIsSentWithItsExactDigits() async throws {
        // Given
        respond(200, #"{"jsonrpc":"2.0","id":"1","result":"ok"}"#)
        let request = StringRequest(method: "transfer", parameters: .positioned([UInt64.max, Int64.min]), requestID: .string("1"))

        // When
        _ = try await request.request()

        // Then
        let body = try XCTUnwrap(String(data: XCTUnwrap(JRPCStubProtocol.recorded.first).body, encoding: .utf8))
        XCTAssertTrue(body.contains("[18446744073709551615,-9223372036854775808]"), "Unexpected body: \(body)")
    }

    func testBatchUInt64ParameterIsSentWithItsExactDigits() async throws {
        respond(200, #"[{"jsonrpc":"2.0","id":"1","result":"ok"}]"#)

        _ = try await HarborJRPC.batch([StringRequest(method: "transfer", parameters: .named(["amount": UInt64.max]), requestID: .string("1"))])

        let body = try XCTUnwrap(String(data: XCTUnwrap(JRPCStubProtocol.recorded.first).body, encoding: .utf8))
        XCTAssertTrue(body.contains(#""amount":18446744073709551615"#), "Unexpected body: \(body)")
    }

    func testUnencodableParameterFailsWithoutANetworkCall() async throws {
        let request = StringRequest(method: "eth_call", parameters: .positioned([Double.nan]))

        let response = await request.requestResult()
        guard case .error(.codable(let modelName, _)) = response else {
            return XCTFail("Expected codable error but got: \(response)")
        }
        XCTAssertEqual(modelName, "HJRPCParams")

        do {
            _ = try await HarborJRPC.batch([StringRequest(method: "a", parameters: .named(["x": Double.infinity]))])
            XCTFail("Expected batch to throw")
        } catch HJRPCRequestError.codable(let modelName, _) {
            XCTAssertEqual(modelName, "HJRPCParams")
        }

        do {
            try await NotificationRequest(parameters: .positioned([Double.nan])).notify()
            XCTFail("Expected notify() to throw")
        } catch HJRPCRequestError.codable {
            // Expected.
        }

        XCTAssertTrue(JRPCStubProtocol.recorded.isEmpty, "Nothing may be sent when the parameters cannot be encoded")
    }

    // MARK: - F29 Notifications

    func testNotificationSucceedsWithEmptyOrWhitespaceBody() async throws {
        for body in ["", " \n\t\r\n"] {
            respond(200, body)
            try await NotificationRequest().notify()
        }
        respond(204, "")
        try await NotificationRequest().notify()
    }

    func testNotificationWithNonJSON2xxBodyThrows() async throws {
        respond(200, "<html>Welcome</html>")

        do {
            try await NotificationRequest().notify()
            XCTFail("Expected notify() to throw")
        } catch HJRPCRequestError.codable {
            // Expected.
        }
    }

    func testNotificationWithErrorEnvelopeIn2xxThrowsJRPCError() async throws {
        respond(200, #"{"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"},"id":null}"#)

        do {
            try await NotificationRequest().notify()
            XCTFail("Expected notify() to throw")
        } catch HJRPCRequestError.jrpcError(let error) {
            XCTAssertEqual(error.code, -32601)
        }
    }

    func testEmptyBatchReturnsWithoutANetworkCall() async throws {
        let responses = try await HarborJRPC.batch([])

        XCTAssertTrue(responses.isEmpty)
        XCTAssertTrue(JRPCStubProtocol.recorded.isEmpty)
    }

    func testNotificationOnlyBatchWithEmptyBodyReturnsNoResponses() async throws {
        respond(200, "  ")

        let responses = try await HarborJRPC.batch([NotificationRequest(), NotificationRequest()])

        XCTAssertTrue(responses.isEmpty)
        XCTAssertEqual(JRPCStubProtocol.recorded.count, 1)
    }

    func testNotificationOnlyBatchWithNonJSONBodyThrows() async throws {
        respond(200, "<html>Welcome</html>")

        do {
            _ = try await HarborJRPC.batch([NotificationRequest()])
            XCTFail("Expected batch to throw")
        } catch HJRPCRequestError.codable {
            // Expected.
        }
    }

    func testNotificationOnlyBatchWithNon2xxThrows() async throws {
        respond(503, "")

        do {
            _ = try await HarborJRPC.batch([NotificationRequest(), NotificationRequest()])
            XCTFail("Expected batch to throw")
        } catch HJRPCRequestError.api(let statusCode, _) {
            XCTAssertEqual(statusCode, 503)
        }
    }

    func testBatchWithRequestsAnsweredWithEmptyBodyThrowsInvalidResponse() async throws {
        respond(200, "")

        do {
            _ = try await HarborJRPC.batch([StringRequest(method: "a", requestID: .string("1"))])
            XCTFail("Expected batch to throw")
        } catch HJRPCRequestError.invalidResponse {
            // Expected.
        }
    }

    // MARK: - Endpoint Override

    func testEndpointOverridesTheConfiguredURL() async throws {
        respond(200, #"{"jsonrpc":"2.0","id":"1","result":"0x1"}"#)

        _ = try await StringRequest(method: "eth_chainId", requestID: .string("1"),
                                    endpoint: URL(string: "https://other.example.com/rpc")).request()

        XCTAssertEqual(JRPCStubProtocol.recorded.first?.url?.absoluteString, "https://other.example.com/rpc")
    }

    func testEndpointWorksWithoutAConfiguredURL() async throws {
        HJRPCRequestManager.config.url = ""
        respond(200, #"[{"jsonrpc":"2.0","id":"1","result":"0x1"}]"#)
        let endpoint = URL(string: "https://other.example.com/rpc")

        let responses = try await HarborJRPC.batch([StringRequest(method: "a", requestID: .string("1"), endpoint: endpoint)])

        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(JRPCStubProtocol.recorded.first?.url, endpoint)
    }

    func testBatchWithDifferentEndpointsThrowsMalformedRequest() async throws {
        do {
            _ = try await HarborJRPC.batch([
                StringRequest(method: "a", requestID: .string("1")),
                StringRequest(method: "b", requestID: .string("2"), endpoint: URL(string: "https://other.example.com/rpc")),
            ])
            XCTFail("Expected batch to throw")
        } catch HJRPCRequestError.malformedRequest {
            // Expected.
        }
        XCTAssertTrue(JRPCStubProtocol.recorded.isEmpty)
    }

    // MARK: - Error Mapping

    func testTransportErrorsMapToMatchingJRPCCases() async {
        guard case .cannotConnectToHost = HJRPCRequestError.getError(hRequestError: .cannotConnectToHost) else {
            return XCTFail("Expected cannotConnectToHost")
        }
        guard case .cannotFindHost = HJRPCRequestError.getError(hRequestError: .cannotFindHost) else {
            return XCTFail("Expected cannotFindHost")
        }
        let underlying = CocoaError(.fileNoSuchFile)
        guard case .unknown(let error) = HJRPCRequestError.getError(hRequestError: .unknown(underlying)) else {
            return XCTFail("Expected unknown")
        }
        XCTAssertEqual((error as? CocoaError)?.code, .fileNoSuchFile)
        XCTAssertEqual(HJRPCRequestError.cannotConnectToHost.errorDescription, "Cannot connect to the specified host.")
        XCTAssertTrue(HJRPCRequestError.unknown(underlying).errorDescription?.hasPrefix("Unexpected error:") == true)
    }
}

// MARK: - Test Helpers

private struct StringRequest: HJRPCRequestProtocol {
    typealias Model = String

    let method: String
    let parameters: HJRPCParams?
    let requestID: HJRPCId?
    let headers: [String: String]?
    let retryPolicy: HRetryPolicy?
    let endpoint: URL?

    init(method: String,
         parameters: HJRPCParams? = nil,
         requestID: HJRPCId? = nil,
         headers: [String: String]? = nil,
         retryPolicy: HRetryPolicy? = nil,
         endpoint: URL? = nil) {
        self.method = method
        self.parameters = parameters
        self.requestID = requestID
        self.headers = headers
        self.retryPolicy = retryPolicy
        self.endpoint = endpoint
    }
}

private struct DebugStringRequest: HJRPCRequestProtocol, HDebugRequestProtocol {
    typealias Model = String

    let method: String
    let debugType: HDebugRequestType
    let requestID: HJRPCId?
    let headers: [String: String]?

    init(method: String, debugType: HDebugRequestType, requestID: HJRPCId? = nil, headers: [String: String]? = nil) {
        self.method = method
        self.debugType = debugType
        self.requestID = requestID
        self.headers = headers
    }
}

private struct JSONValueRequest: HJRPCRequestProtocol {
    typealias Model = HJSONValue

    let method: String
    let requestID: HJRPCId?
}

private struct NotificationRequest: HJRPCRequestProtocol {
    typealias Model = String

    let method: String = "eth_unsubscribe"
    let isNotification: Bool = true
    let parameters: HJRPCParams?

    init(parameters: HJRPCParams? = nil) {
        self.parameters = parameters
    }
}
