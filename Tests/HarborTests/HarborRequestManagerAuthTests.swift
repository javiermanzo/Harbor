//
//  HarborRequestManagerAuthTests.swift
//  Harbor
//
//  Created by Jalil on 05/11/24.
//

import XCTest
@testable import Harbor

private final class MockAuthProvider: HAuthProviderProtocol {
    func getAuthorizationHeader() async -> HAuthorizationHeader {
        return HAuthorizationHeader(key: "Authorization", value: "Bearer mock_token")
    }

    func authFailed() async {
        // Handle auth failure logic if needed.
    }
}

extension HRequestError: Equatable {
    public static func ==(lhs: HRequestError, rhs: HRequestError) -> Bool {
        switch (lhs, rhs) {
        case (.authProviderNeeded, .authProviderNeeded):
            return true
        case (.noConnection, .noConnection):
            return true
        case (.malformedRequest, .malformedRequest):
            return true
        case (.timeout, .timeout):
            return true
        case (.invalidHttpResponse, .invalidHttpResponse):
            return true
        case (.codable(let lhsModel, _), .codable(let rhsModel, _)):
            return lhsModel == rhsModel
        case (.api(let lhsStatusCode, _), .api(let rhsStatusCode, _)):
            return lhsStatusCode == rhsStatusCode
        default:
            return false
        }
    }
}

@HRequestManagerActor
final class HarborRequestManagerAuthTests: XCTestCase {

    func testAddAuthCredentialsIfNeededWithAuthSuccess() async throws {
        // Given
        let mockAuthProvider = MockAuthProvider()
        HConfig.shared.authProvider = mockAuthProvider

        let mockRequest = MockGetRequest<String>(needsAuth: true, url: "https://example.com/mock_endpoint")

        // When
        let result = await HRequestManager.addAuthCredentialsIfNeeded(mockRequest)

        // Then
        guard case .success(let modifiedRequest) = result else {
            XCTFail("Expected modified request with auth credentials")
            return
        }
        XCTAssertEqual(modifiedRequest.headerParameters?["Authorization"], "Bearer mock_token", "Expected authorization header to be set correctly")
    }

    func testAddAuthCredentialsIfNeededWithoutAuth() async throws {
        // Given
        let mockAuthProvider = MockAuthProvider()
        HConfig.shared.authProvider = mockAuthProvider

        let mockRequest = MockGetRequest<String>(needsAuth: false, url: "https://example.com/mock_endpoint")

        // When
        let result = await HRequestManager.addAuthCredentialsIfNeeded(mockRequest)

        // Then
        guard case .success(let modifiedRequest) = result else {
            XCTFail("Expected original request since auth is not needed")
            return
        }
        XCTAssertNil(modifiedRequest.headerParameters?["Authorization"], "Expected no authorization header since auth is not needed")
    }

    func testAddAuthCredentialsIfNeededWithoutProviderFails() async throws {
        // Given
        HConfig.shared.authProvider = nil

        let mockRequest = MockGetRequest<String>(needsAuth: true, url: "https://example.com/mock_endpoint")

        // When
        let result = await HRequestManager.addAuthCredentialsIfNeeded(mockRequest)

        // Then
        guard case .failure(let error) = result, case .authProviderNeeded = error else {
            XCTFail("Expected .authProviderNeeded but got: \(result)")
            return
        }
    }
}
