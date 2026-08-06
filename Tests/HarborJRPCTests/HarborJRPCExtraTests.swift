import XCTest
@testable import HarborJRPC
@testable import Harbor

final class HarborJRPCExtraTests: XCTestCase {

    func testHJRPCResultDecoding() throws {
        // Test successful result
        let successJSON = """
        {
            "jsonrpc": "2.0",
            "id": 1,
            "result": {"key": "value"}
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let successResult = try decoder.decode(HJRPCResult<HJSONValue>.self, from: successJSON)
        XCTAssertEqual(successResult.jsonrpc, "2.0")
        XCTAssertEqual(successResult.id, .number(1))
        XCTAssertEqual(successResult.result, .object(["key": .string("value")]))
        XCTAssertNil(successResult.error)
        
        // Test error result
        let errorJSON = """
        {
            "jsonrpc": "2.0",
            "id": "abc",
            "error": {"code": -32600, "message": "Invalid Request"}
        }
        """.data(using: .utf8)!
        
        let errorResult = try decoder.decode(HJRPCResult<HJSONValue>.self, from: errorJSON)
        XCTAssertEqual(errorResult.id, .string("abc"))
        XCTAssertNil(errorResult.result)
        XCTAssertEqual(errorResult.error?.code, -32600)
        
        // Test null result
        let nullJSON = """
        {
            "jsonrpc": "2.0",
            "id": null,
            "result": null
        }
        """.data(using: .utf8)!
        
        let nullResult = try decoder.decode(HJRPCResult<HJSONValue>.self, from: nullJSON)
        XCTAssertTrue(nullResult.resultIsNull)
        XCTAssertNil(nullResult.id)
        XCTAssertNil(nullResult.result)
    }

    func testHJSONValue() throws {
        // Test anyValue init
        XCTAssertEqual(HJSONValue(anyValue: NSNull()), .null)
        XCTAssertEqual(HJSONValue(anyValue: "test"), .string("test"))
        XCTAssertEqual(HJSONValue(anyValue: NSNumber(value: true)), .bool(true))
        XCTAssertEqual(HJSONValue(anyValue: NSNumber(value: 3.14)), .double(3.14))
        XCTAssertEqual(HJSONValue(anyValue: NSNumber(value: 42)), .int(42))
        XCTAssertEqual(HJSONValue(anyValue: [1, 2]), .array([.int(1), .int(2)]))
        XCTAssertEqual(HJSONValue(anyValue: ["a": "b"]), .object(["a": .string("b")]))
        XCTAssertNil(HJSONValue(anyValue: Date())) // Invalid type
        
        // Test anyValue export
        XCTAssertTrue(HJSONValue.null.anyValue is NSNull)
        XCTAssertEqual(HJSONValue.string("test").anyValue as? String, "test")
        XCTAssertEqual(HJSONValue.bool(true).anyValue as? Bool, true)
        XCTAssertEqual(HJSONValue.double(3.14).anyValue as? Double, 3.14)
        XCTAssertEqual(HJSONValue.int(42).anyValue as? Int, 42)
        XCTAssertEqual((HJSONValue.array([.int(1)]).anyValue as? [Int])?.first, 1)
        XCTAssertEqual((HJSONValue.object(["a": .string("b")]).anyValue as? [String: String])?["a"], "b")
    }

    func testHJRPCRequestError() {
        // Test getError mapping
        let urlError = URLError(.notConnectedToInternet)
        let mappings: [(HRequestError, HJRPCRequestError)] = [
            (.api(statusCode: 404, data: Data()), .api(statusCode: 404, data: Data())),
            (.invalidHttpResponse, .invalidHttpResponse),
            (.invalidRequest, .invalidRequest),
            (.authProviderNeeded, .authProviderNeeded),
            (.authNeeded, .authNeeded),
            (.codable(modelName: "Test", error: urlError), .codable(modelName: "Test", error: urlError)),
            (.noConnection, .noConnection),
            (.malformedRequest(reason: "test"), .malformedRequest(reason: "test")),
            (.timeout, .timeout),
            (.cannotFindHost, .cannotFindHost),
            (.cancelled, .cancelled),
            (.certificate, .certificate),
            (.noCachedDataFound, .noCachedDataFound),
            (.networkFailure(urlError), .networkFailure(urlError))
        ]
        
        for (hError, jrpcError) in mappings {
            let mapped = HJRPCRequestError.getError(hRequestError: hError)
            XCTAssertEqual(mapped.localizedDescription, jrpcError.localizedDescription)
        }
        
        // Test localized descriptions directly
        XCTAssertEqual(HJRPCRequestError.api(statusCode: 500, data: Data()).errorDescription, "The API returned an error with status code 500.")
        XCTAssertEqual(HJRPCRequestError.urlNeeded.errorDescription, "The JSON-RPC URL is not set. Configure it with HarborJRPC.setURL(_:) or HarborJRPC.configure(url:jrpcVersion:).")
        XCTAssertEqual(HJRPCRequestError.invalidResponse.errorDescription, "The server response is not a valid JSON-RPC response.")
        XCTAssertEqual(HJRPCRequestError.idMismatch(expected: .number(1), actual: .number(2)).errorDescription, "The response id (2) does not match the request id (1).")
        XCTAssertEqual(HJRPCRequestError.jrpcError(error: HJRPCError(code: 1, message: "msg", data: nil)).errorDescription, "JSON-RPC error 1: msg")
    }
}
