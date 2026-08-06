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
        await Harbor.setSSLPinningKeys(nil)
        await Harbor.clearMTLS()
        await Harbor.setMocksOnlyInDebug(true)
        await Harbor.removeAllMocks()
    }
    
    override func tearDown() async throws {
        // Reset all configurations to default
        await Harbor.setDefaultHeaderParameters(nil)
        await Harbor.setAuthProvider(nil)
        await Harbor.setCustomURLSession(URLSession.shared)
        await Harbor.setSSLPinningKeys(nil)
        await Harbor.clearMTLS()
        await Harbor.setMocksOnlyInDebug(true)
        await Harbor.removeAllMocks()
    }
    
    // MARK: - Default Headers Tests

    func testSetDefaultHeaderParameters() async throws {
        // Given
        let headers = [
            "X-API-Key": "test-api-key",
            "User-Agent": "Harbor/1.0"
        ]

        // When
        await Harbor.setDefaultHeaderParameters(headers)

        // Then the default headers reach the built URLRequest
        let request = TestConfigRequest()
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-API-Key"), "test-api-key")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "User-Agent"), "Harbor/1.0")
    }

    func testSetDefaultHeaderParametersWithNil() async throws {
        // Given
        let headers = ["X-API-Key": "test-key"]
        await Harbor.setDefaultHeaderParameters(headers)

        // When
        await Harbor.setDefaultHeaderParameters(nil)

        // Then the previously set default header is no longer applied
        let request = TestConfigRequest()
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "X-API-Key"))
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
        
        let mock = HMock(request: TestConfigRequest.self, statusCode: 200, jsonResponse: jsonString)
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

        // Then the provider's header is resolved for an auth-needing request
        let request = TestAuthenticatedConfigRequest()
        let result = await HRequestManager.authorizationHeaderIfNeeded(for: request)
        guard case .success(let header) = result else {
            return XCTFail("Expected the provider's authorization header but got: \(result)")
        }
        XCTAssertEqual(header?.value, "Bearer test-token")
    }

    func testSetAuthProviderWithNil() async throws {
        // Given
        let authProvider = TestAuthProvider()
        await Harbor.setAuthProvider(authProvider)

        // When
        await Harbor.setAuthProvider(nil)

        // Then an auth-needing request reports the missing provider instead of resolving a header
        let request = TestAuthenticatedConfigRequest()
        let result = await HRequestManager.authorizationHeaderIfNeeded(for: request)
        guard case .failure(let error) = result, case .authProviderNeeded = error else {
            return XCTFail("Expected .authProviderNeeded after clearing the provider but got: \(result)")
        }
    }
    
    func testAuthProviderAppliedToRequest() async throws {
        // Given
        let authProvider = TestAuthProvider()
        await Harbor.setAuthProvider(authProvider)
        
        let mockResponse = TestConfigData(value: "auth-test")
        let jsonData = try JSONEncoder().encode(mockResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = HMock(request: TestAuthenticatedConfigRequest.self, statusCode: 200, jsonResponse: jsonString)
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

        // Then the user-provided session is used as-is by the manager
        let request = TestConfigRequest()
        let session = await HRequestManager.getURLSession(for: request)
        XCTAssertTrue(session === customSession)
    }

    func testSetCustomURLSessionWithDefault() async throws {
        // Given
        let customSession = URLSession(configuration: .default)
        await Harbor.setCustomURLSession(customSession)

        // When
        await Harbor.setCustomURLSession(URLSession.shared)

        // Then the shared session is the one used going forward
        let request = TestConfigRequest()
        let session = await HRequestManager.getURLSession(for: request)
        XCTAssertTrue(session === URLSession.shared)
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
        
        let mock = HMock(request: TestConfigRequest.self, statusCode: 200, jsonResponse: jsonString)
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
    
    // MARK: - Timeout Configuration Tests

    func testSetDefaultTimeoutInterval() async throws {
        // Given no custom session, so the internally built session reflects the config
        await clearCustomURLSession()

        // When
        await Harbor.setDefaultTimeoutInterval(30)

        // Then the timeout reaches the internally built session configuration
        let request = TestConfigRequest()
        let session = await HRequestManager.getURLSession(for: request)
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 30, accuracy: 0.001)
    }


    // MARK: - Mock Configuration Tests

    func testSetMocksOnlyInDebugTrue() async throws {
        // When
        await Harbor.setMocksOnlyInDebug(true)

        // Then the build rule remains in effect (override stays cleared)
        let override = await mocksEnabledOverrideValue()
        XCTAssertNil(override)
    }

    func testSetMocksOnlyInDebugFalse() async throws {
        // When
        await Harbor.setMocksOnlyInDebug(false)

        // Then the override is still unset; only the build rule flag flipped
        let override = await mocksEnabledOverrideValue()
        XCTAssertNil(override)
    }
    
    func testMocksOnlyInDebugConfiguration() async throws {
        // Given
        await Harbor.setMocksOnlyInDebug(false) // Allow mocks in all modes
        
        let mockResponse = TestConfigData(value: "mock-config-test")
        let jsonData = try JSONEncoder().encode(mockResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = HMock(request: TestConfigRequest.self, statusCode: 200, jsonResponse: jsonString)
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
        
        let mock = HMock(request: TestFullyConfiguredRequest.self, statusCode: 200, jsonResponse: jsonString)
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
        await Harbor.setMocksEnabled(false)

        // When - Reset all configurations
        await Harbor.setDefaultHeaderParameters(nil)
        await Harbor.setAuthProvider(nil)
        await Harbor.setCustomURLSession(URLSession.shared)
        await Harbor.setMocksOnlyInDebug(true)
        await Harbor.setMocksEnabled(nil)

        // Then the cleared defaults are observable on a built request
        let request = TestConfigRequest()
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "X-Test"))
        let override = await mocksEnabledOverrideValue()
        XCTAssertNil(override)
    }

    // MARK: - Mocks Enabled Override

    func testMocksEnabledOverrideTakesPrecedence() async throws {
        // Given mocks would otherwise be enabled in DEBUG
        await Harbor.setMocksEnabled(false)
        let disabled = await mocksEnabledValue()
        XCTAssertEqual(disabled, false)

        // And re-enabling restores the value
        await Harbor.setMocksEnabled(true)
        let enabled = await mocksEnabledValue()
        XCTAssertEqual(enabled, true)

        // And clearing the override falls back to the build rule
        await Harbor.setMocksEnabled(nil)
    }
}

// MARK: - Actor-isolated config accessors

@HRequestManagerActor
private func clearCustomURLSession() {
    HConfig.shared.customURLSession = nil
}

@HRequestManagerActor
private func mocksEnabledOverrideValue() -> Bool? {
    HConfig.shared.mocksEnabledOverride
}

@HRequestManagerActor
private func mocksEnabledValue() -> Bool {
    HConfig.shared.mocksEnabled
}

// MARK: - Test Models

private struct TestConfigData: HModel {
    let value: String
}

// MARK: - Test Auth Provider

private final class TestAuthProvider: HAuthProviderProtocol, @unchecked Sendable {
    func getAuthorizationHeader() async -> HAuthorizationHeader? {
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
