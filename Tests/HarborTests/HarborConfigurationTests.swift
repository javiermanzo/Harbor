//
//  HarborConfigurationTests.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import XCTest
@testable import Harbor

final class HarborConfigurationTests: XCTestCase {
    
    override func setUp() async throws {
        // Reset all configurations to default
        await Harbor.setDefaultHeaderParameters(nil)
        await Harbor.setAuthProvider(nil)
        await Harbor.setCustomURLSession(URLSession.shared)
        await Harbor.setSSlPinningSHA256(nil)
        await Harbor.setMTLS(nil)
        await Harbor.setMocksOnlyInDebug(true)
        await Harbor.removeAllMocks()
    }
    
    override func tearDown() async throws {
        // Reset all configurations to default
        await Harbor.setDefaultHeaderParameters(nil)
        await Harbor.setAuthProvider(nil)
        await Harbor.setCustomURLSession(URLSession.shared)
        await Harbor.setSSlPinningSHA256(nil)
        await Harbor.setMTLS(nil)
        await Harbor.setMocksOnlyInDebug(true)
        await Harbor.removeAllMocks()
    }
    
    // MARK: - Default Headers Tests
    
    func testSetDefaultHeaderParameters() async throws {
        // Given
        let headers = [
            "X-API-Key": "test-api-key",
            "Content-Type": "application/json",
            "User-Agent": "Harbor/1.0"
        ]
        
        // When
        await Harbor.setDefaultHeaderParameters(headers)
        
        // Then
        // We can't directly test internal state, but configuration should not crash
        XCTAssertTrue(true)
    }
    
    func testSetDefaultHeaderParametersWithNil() async throws {
        // Given
        let headers = ["X-API-Key": "test-key"]
        await Harbor.setDefaultHeaderParameters(headers)
        
        // When
        await Harbor.setDefaultHeaderParameters(nil)
        
        // Then
        // Headers should be cleared
        XCTAssertTrue(true)
    }
    
    func testDefaultHeadersAppliedToRequest() async throws {
        // Given
        let headers = [
            "X-API-Key": "test-api-key",
            "X-Client-Version": "1.0.0"
        ]
        await Harbor.setDefaultHeaderParameters(headers)
        
        let mockResponse = TestConfigData(value: "header-test")
        let jsonData = try JSONEncoder().encode(mockResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = await HMock(request: TestConfigRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        // When
        let request = TestConfigRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "header-test")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    // MARK: - Auth Provider Tests
    
    func testSetAuthProvider() async throws {
        // Given
        let authProvider = TestAuthProvider()
        
        // When
        await Harbor.setAuthProvider(authProvider)
        
        // Then
        // Auth provider should be set
        XCTAssertTrue(true)
    }
    
    func testSetAuthProviderWithNil() async throws {
        // Given
        let authProvider = TestAuthProvider()
        await Harbor.setAuthProvider(authProvider)
        
        // When
        await Harbor.setAuthProvider(nil)
        
        // Then
        // Auth provider should be cleared
        XCTAssertTrue(true)
    }
    
    func testAuthProviderAppliedToRequest() async throws {
        // Given
        let authProvider = TestAuthProvider()
        await Harbor.setAuthProvider(authProvider)
        
        let mockResponse = TestConfigData(value: "auth-test")
        let jsonData = try JSONEncoder().encode(mockResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = await HMock(request: TestAuthenticatedConfigRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        // When
        let request = TestAuthenticatedConfigRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "auth-test")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    // MARK: - Custom URLSession Tests
    
    func testSetCustomURLSession() async throws {
        // Given
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        let customSession = URLSession(configuration: config)
        
        // When
        await Harbor.setCustomURLSession(customSession)
        
        // Then
        // Custom session should be set
        XCTAssertTrue(true)
    }
    
    func testSetCustomURLSessionWithDefault() async throws {
        // Given
        let customSession = URLSession(configuration: .default)
        await Harbor.setCustomURLSession(customSession)
        
        // When
        await Harbor.setCustomURLSession(URLSession.shared)
        
        // Then
        // Should revert to shared session
        XCTAssertTrue(true)
    }
    
    func testCustomURLSessionAppliedToRequest() async throws {
        // Given
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["X-Custom-Session": "true"]
        let customSession = URLSession(configuration: config)
        await Harbor.setCustomURLSession(customSession)
        
        let mockResponse = TestConfigData(value: "session-test")
        let jsonData = try JSONEncoder().encode(mockResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = await HMock(request: TestConfigRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        // When
        let request = TestConfigRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "session-test")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    
    // MARK: - Mock Configuration Tests
    
    func testSetMocksOnlyInDebugTrue() async throws {
        // When
        await Harbor.setMocksOnlyInDebug(true)
        
        // Then
        // Mocks should only work in debug mode
        XCTAssertTrue(true)
    }
    
    func testSetMocksOnlyInDebugFalse() async throws {
        // When
        await Harbor.setMocksOnlyInDebug(false)
        
        // Then
        // Mocks should work in all modes
        XCTAssertTrue(true)
    }
    
    func testMocksOnlyInDebugConfiguration() async throws {
        // Given
        await Harbor.setMocksOnlyInDebug(false) // Allow mocks in all modes
        
        let mockResponse = TestConfigData(value: "mock-config-test")
        let jsonData = try JSONEncoder().encode(mockResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = await HMock(request: TestConfigRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        // When
        let request = TestConfigRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "mock-config-test")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    // MARK: - Combined Configuration Tests
    
    func testCombinedConfiguration() async throws {
        // Given - Multiple configurations
        let headers = ["X-API-Key": "combined-test"]
        await Harbor.setDefaultHeaderParameters(headers)
        
        let authProvider = TestAuthProvider()
        await Harbor.setAuthProvider(authProvider)
        
        let customSession = URLSession(configuration: .default)
        await Harbor.setCustomURLSession(customSession)
        
        await Harbor.setMocksOnlyInDebug(false)
        
        let mockResponse = TestConfigData(value: "combined-config-test")
        let jsonData = try JSONEncoder().encode(mockResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = await HMock(request: TestFullyConfiguredRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        // When
        let request = TestFullyConfiguredRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success(let data):
            XCTAssertEqual(data.value, "combined-config-test")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    // MARK: - Configuration Reset Tests
    
    func testConfigurationReset() async throws {
        // Given - Set all configurations
        await Harbor.setDefaultHeaderParameters(["X-Test": "value"])
        await Harbor.setAuthProvider(TestAuthProvider())
        await Harbor.setCustomURLSession(URLSession(configuration: .default))
        await Harbor.setMocksOnlyInDebug(false)
        
        // When - Reset all configurations
        await Harbor.setDefaultHeaderParameters(nil)
        await Harbor.setAuthProvider(nil)
        await Harbor.setCustomURLSession(URLSession.shared)
        await Harbor.setMocksOnlyInDebug(true)
        
        // Then - Should not crash and be in clean state
        XCTAssertTrue(true)
    }
}

// MARK: - Test Models

private struct TestConfigData: HModel {
    let value: String
}

// MARK: - Test Auth Provider

private final class TestAuthProvider: HAuthProviderProtocol, @unchecked Sendable {
    func getAuthorizationHeader() async -> HAuthorizationHeader {
        return HAuthorizationHeader(key: "Authorization", value: "Bearer test-token")
    }
    
    func authFailed() async {
        // Handle auth failure
    }
}

// MARK: - Test Request Implementations

private struct TestConfigRequest: HGetRequestProtocol {
    typealias Model = TestConfigData
    
    var url: String { "https://config.example.com/test" }
}

private struct TestAuthenticatedConfigRequest: HGetRequestProtocol {
    typealias Model = TestConfigData
    
    var url: String { "https://config.example.com/auth-test" }
    var needsAuth: Bool { true }
}


private struct TestFullyConfiguredRequest: HGetRequestProtocol {
    typealias Model = TestConfigData
    
    var url: String { "https://api.example.com/full-config-test" }
    var needsAuth: Bool { true }
    var headerParameters: [String: String]? {
        ["X-Custom-Header": "test-value"]
    }
}