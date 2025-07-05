import XCTest
@testable import HarborJRPC

final class HarborJRPCTests: XCTestCase {

    override func setUp() async throws {
        await HarborJRPC.setURL("https://api.example.com/rpc")
    }

    func testJRPCVersionConfiguration() async throws {
        // Test setting JRPC version 1.0
        await HarborJRPC.setJRPCVersion("1.0")
        
        // Verify configuration doesn't crash
        XCTAssertTrue(true)
        
        // Reset to default
        await HarborJRPC.setJRPCVersion("2.0")
        
        // Verify reset doesn't crash
        XCTAssertTrue(true)
    }
    
    func testJRPCRequestProtocolProperties() throws {
        // Test that JRPC request protocols have correct default values
        let request = TestRequest(method: "test_method")
        
        XCTAssertEqual(request.method, "test_method")
        XCTAssertFalse(request.needsAuth)
        XCTAssertNil(request.retries)
        XCTAssertNil(request.headers)
        XCTAssertNil(request.parameters)
    }
    
    func testJRPCRequestProtocolWithAuth() throws {
        // Test authenticated request properties
        let request = TestAuthenticatedRequest(method: "protected_method")
        
        XCTAssertEqual(request.method, "protected_method")
        XCTAssertTrue(request.needsAuth)
        XCTAssertNil(request.parameters)
    }
    
    func testJRPCRequestProtocolWithRetries() throws {
        // Test request with retries
        let request = TestRetryRequest(method: "retry_method", retries: 3)
        
        XCTAssertEqual(request.method, "retry_method")
        XCTAssertEqual(request.retries, 3)
        XCTAssertFalse(request.needsAuth)
    }
    
    func testJRPCRequestProtocolWithParameters() throws {
        // Test request with parameters
        let params = ["param1": "value1", "param2": 42] as [String: Any]
        let request = TestRequestWithParameters(method: "method_with_params", parameters: params)
        
        XCTAssertEqual(request.method, "method_with_params")
        XCTAssertNotNil(request.parameters)
        
        if let requestParams = request.parameters {
            XCTAssertEqual(requestParams["param1"] as? String, "value1")
            XCTAssertEqual(requestParams["param2"] as? Int, 42)
        }
    }
    
    func testJRPCURLConfiguration() async throws {
        // Test URL configuration
        let testURL = "https://test.example.com/jsonrpc"
        await HarborJRPC.setURL(testURL)
        
        // Configuration should not crash
        XCTAssertTrue(true)
        
        // Reset to original
        await HarborJRPC.setURL("https://api.example.com/rpc")
    }
}

struct TestRequest: HJRPCRequestProtocol, @unchecked Sendable {
    typealias Model = String
    var method: String = "eth_blockNumber"
    var parameters: [String: Any]?

    init(method: String, parameters: [String : Any]? = nil) {
        self.method = method
        self.parameters = parameters
    }
}


struct TestAuthenticatedRequest: HJRPCRequestProtocol, @unchecked Sendable {
    typealias Model = String
    var method: String
    var parameters: [String: Any]?
    var needsAuth: Bool = true

    init(method: String, parameters: [String : Any]? = nil) {
        self.method = method
        self.parameters = parameters
    }
}

struct TestRetryRequest: HJRPCRequestProtocol, @unchecked Sendable {
    typealias Model = String
    var method: String
    var parameters: [String: Any]?
    var retries: Int?

    init(method: String, parameters: [String : Any]? = nil, retries: Int? = nil) {
        self.method = method
        self.parameters = parameters
        self.retries = retries
    }
}

struct TestRequestWithParameters: HJRPCRequestProtocol, @unchecked Sendable {
    typealias Model = String
    var method: String
    var parameters: [String: Any]?

    init(method: String, parameters: [String : Any]? = nil) {
        self.method = method
        self.parameters = parameters
    }
}

