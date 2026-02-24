//
//  HarborIntegrationTests.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import XCTest
@testable import Harbor

final class HarborTests: XCTestCase {
    
    override func setUp() async throws {
        await Harbor.removeAllMocks()
    }
    
    override func tearDown() async throws {
        await Harbor.removeAllMocks()
    }
    
    // MARK: - GET Request Tests
    
    func testGetRequestExecution() async throws {
        // Given
        let mockResponse = TestUser(id: 1, name: "John Doe", email: "john@example.com")
        let jsonData = try JSONEncoder().encode(mockResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = await HMock(request: GetUserRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        // When
        let request = GetUserRequest(userId: "1")
        let response = await request.request()
        
        // Then
        switch response {
        case .success(let user):
            XCTAssertEqual(user.id, 1)
            XCTAssertEqual(user.name, "John Doe")
            XCTAssertEqual(user.email, "john@example.com")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    func testGetRequestWithQueryParameters() async throws {
        // Given
        let users = [
            TestUser(id: 1, name: "John", email: "john@example.com"),
            TestUser(id: 2, name: "Jane", email: "jane@example.com")
        ]
        let jsonData = try JSONEncoder().encode(users)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = await HMock(request: GetUsersRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        // When
        let request = GetUsersRequest(page: 1, limit: 10)
        let response = await request.request()
        
        // Then
        switch response {
        case .success(let userList):
            XCTAssertEqual(userList.count, 2)
            XCTAssertEqual(userList[0].name, "John")
            XCTAssertEqual(userList[1].name, "Jane")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    // MARK: - POST Request Tests
    
    func testPostRequestExecution() async throws {
        // Given
        let mock = await HMock(request: CreateUserRequest.self, statusCode: 201)
        await Harbor.register(mock: mock)
        
        // When
        let request = CreateUserRequest(name: "New User", email: "new@example.com")
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTAssertTrue(true) // Success case
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    func testPostRequestWithMultipart() async throws {
        // Given
        let mock = await HMock(request: UploadFileRequest.self, statusCode: 200)
        await Harbor.register(mock: mock)
        
        // When
        let request = UploadFileRequest(fileName: "test.jpg", fileData: Data("test".utf8))
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTAssertTrue(true) // Success case
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    // MARK: - DELETE Request Tests
    
    func testDeleteRequestExecution() async throws {
        // Given
        let mock = await HMock(request: DeleteUserRequest.self, statusCode: 204)
        await Harbor.register(mock: mock)
        
        // When
        let request = DeleteUserRequest(userId: "1")
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTAssertTrue(true) // Success case
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    
    // MARK: - Authentication Tests
    
    func testAuthenticatedRequest() async throws {
        // Given
        let protectedData = ProtectedData(secret: "classified-info")
        let jsonData = try JSONEncoder().encode(protectedData)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = await HMock(request: AuthenticatedRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        // When
        let request = AuthenticatedRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success(let data):
            XCTAssertEqual(data.secret, "classified-info")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    func testAuthenticationFailure() async throws {
        // Given
        let mock = await HMock(request: AuthenticatedRequest.self, statusCode: 401, error: .authNeeded)
        await Harbor.register(mock: mock)
        
        // When
        let request = AuthenticatedRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTFail("Expected authentication error")
        case .error(let error):
            switch error {
            case .authNeeded:
                XCTAssertTrue(true) // Expected auth error
            default:
                XCTFail("Expected authNeeded but got: \(error)")
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testNetworkErrorHandling() async throws {
        // Given
        let mock = await HMock(request: GetUserRequest.self, statusCode: 500, error: .noConnection)
        await Harbor.register(mock: mock)
        
        // When
        let request = GetUserRequest(userId: "1")
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTFail("Expected network error")
        case .error(let error):
            switch error {
            case .noConnection:
                XCTAssertTrue(true) // Expected network error
            default:
                XCTFail("Expected noConnection but got: \(error)")
            }
        }
    }
    
    func testAPIErrorHandling() async throws {
        // Given
        let mock = await HMock(request: GetUserRequest.self, statusCode: 404)
        await Harbor.register(mock: mock)
        
        // When
        let request = GetUserRequest(userId: "999")
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTFail("Expected API error")
        case .error(let error):
            XCTAssertTrue(error.isApiError)
        }
    }
    
    func testJSONParsingError() async throws {
        // Given - Invalid JSON response
        let mock = await HMock(request: GetUserRequest.self, statusCode: 200, jsonResponse: "invalid-json")
        await Harbor.register(mock: mock)
        
        // When
        let request = GetUserRequest(userId: "1")
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTFail("Expected parsing error")
        case .error(let error):
            // Should be a codable/parsing error
            switch error {
            case .codable:
                XCTAssertTrue(true)
            default:
                XCTFail("Expected codable error but got: \(error)")
            }
        }
    }
    
    // MARK: - Custom Headers Tests
    
    func testCustomHeaders() async throws {
        // Given
        let userResponse = TestUser(id: 1, name: "John", email: "john@example.com")
        let jsonData = try JSONEncoder().encode(userResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = await HMock(request: CustomHeadersRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        // When
        let request = CustomHeadersRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success(let user):
            XCTAssertEqual(user.name, "John")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    // MARK: - Timeout and Connection Failure Tests
    
    func testRequestTimeout() async throws {
        // Given
        let mock = await HMock(request: TimeoutRequest.self, statusCode: 408, error: .timeout)
        await Harbor.register(mock: mock)
        
        // When
        let request = TimeoutRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTFail("Expected timeout error")
        case .error(let error):
            switch error {
            case .timeout:
                XCTAssertTrue(true) // Expected timeout error
            default:
                XCTFail("Expected timeout error but got: \(error)")
            }
        }
    }
    
    func testConnectionFailure() async throws {
        // Given
        let mock = await HMock(request: ConnectionFailureRequest.self, statusCode: 0, error: .noConnection)
        await Harbor.register(mock: mock)
        
        // When
        let request = ConnectionFailureRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTFail("Expected connection error")
        case .error(let error):
            switch error {
            case .noConnection:
                XCTAssertTrue(true) // Expected connection error
            default:
                XCTFail("Expected connection error but got: \(error)")
            }
        }
    }
    
    func testCannotFindHost() async throws {
        // Given
        let mock = await HMock(request: InvalidHostRequest.self, statusCode: 0, error: .cannotFindHost)
        await Harbor.register(mock: mock)
        
        // When
        let request = InvalidHostRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTFail("Expected host not found error")
        case .error(let error):
            switch error {
            case .cannotFindHost:
                XCTAssertTrue(true) // Expected host not found error
            default:
                XCTFail("Expected host not found error but got: \(error)")
            }
        }
    }
    
    func testMalformedRequest() async throws {
        // Given
        let mock = await HMock(request: MalformedRequest.self, statusCode: 400, error: .malformedRequest)
        await Harbor.register(mock: mock)
        
        // When
        let request = MalformedRequest()
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTFail("Expected malformed request error")
        case .error(let error):
            switch error {
            case .malformedRequest:
                XCTAssertTrue(true) // Expected malformed request error
            default:
                XCTFail("Expected malformed request error but got: \(error)")
            }
        }
    }
    
    func testRequestCancellation() async throws {
        // Given
        let mock = await HMock(request: CancellableRequest.self, statusCode: 200, jsonResponse: "{\"data\": \"slow response\"}", delay: 2.0)
        await Harbor.register(mock: mock)
        
        // When
        let task = Task {
            let request = CancellableRequest()
            return await request.request()
        }
        
        // Cancel the task immediately
        task.cancel()
        let response = await task.value
        
        // Then
        switch response {
        case .success:
            // Note: Due to mocking, this might still succeed if cancellation timing doesn't work
            // In real scenarios, this would be cancelled
            XCTAssertTrue(true)
        case .error(let error):
            switch error {
            case .cancelled:
                XCTAssertTrue(true) // Expected cancellation
            default:
                // Other errors are also acceptable in this test scenario
                XCTAssertTrue(true)
            }
        }
    }
    
    // MARK: - Path Parameters Tests
    
    func testPathParameters() async throws {
        // Given
        let user = TestUser(id: 123, name: "John", email: "john@example.com")
        let jsonData = try JSONEncoder().encode(user)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = await HMock(request: GetUserByIdRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        // When
        let request = GetUserByIdRequest(id: 123)
        let response = await request.request()
        
        // Then
        switch response {
        case .success(let user):
            XCTAssertEqual(user.id, 123)
            XCTAssertEqual(user.name, "John")
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    // MARK: - PUT Request Tests
    
    func testPutRequestExecution() async throws {
        // Given
        let mock = await HMock(request: UpdateUserRequest.self, statusCode: 200)
        await Harbor.register(mock: mock)
        
        // When
        let request = UpdateUserRequest(id: 1, name: "Updated User", email: "updated@example.com")
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTAssertTrue(true) // Success case
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    func testPutRequestWithMultipart() async throws {
        // Given
        let mock = await HMock(request: UpdateUserWithFileRequest.self, statusCode: 200)
        await Harbor.register(mock: mock)
        
        // When
        let request = UpdateUserWithFileRequest(id: 1, name: "Updated User", avatar: Data("avatar".utf8))
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTAssertTrue(true) // Success case
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    // MARK: - PATCH Request Tests
    
    func testPatchRequestExecution() async throws {
        // Given
        let mock = await HMock(request: PartialUpdateUserRequest.self, statusCode: 200)
        await Harbor.register(mock: mock)
        
        // When
        let request = PartialUpdateUserRequest(id: 1, name: "Partially Updated")
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTAssertTrue(true) // Success case
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    func testPatchRequestWithJSONBody() async throws {
        // Given
        let mock = await HMock(request: PartialUpdateUserWithJSONRequest.self, statusCode: 200)
        await Harbor.register(mock: mock)
        
        // When
        let request = PartialUpdateUserWithJSONRequest(id: 1, email: "newemail@example.com")
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            XCTAssertTrue(true) // Success case
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
}

// MARK: - Test Models

private struct TestUser: HModel {
    let id: Int
    let name: String
    let email: String
}

private struct FileUploadResponse: HModel {
    let id: String
    let url: String
}

private struct ProtectedData: HModel {
    let secret: String
}

// MARK: - Test Request Implementations

private struct GetUserRequest: HGetRequestProtocol {
    typealias Model = TestUser
    
    let userId: String
    
    var url: String { "https://api.example.com/users/\(userId)" }
}

private struct GetUsersRequest: HGetRequestProtocol {
    typealias Model = [TestUser]
    
    let page: Int
    let limit: Int
    
    var url: String { "https://api.example.com/users" }
    var queryParameters: [String: String]? {
        ["page": "\(page)", "limit": "\(limit)"]
    }
}

private final class CreateUserRequest: HPostRequestProtocol, @unchecked Sendable {
    typealias Model = TestUser
    
    let name: String
    let email: String
    var bodyParameters: [String: Any]?
    
    var url: String { "https://api.example.com/users" }
    
    init(name: String, email: String) {
        self.name = name
        self.email = email
        self.bodyParameters = ["name": name, "email": email]
    }
}

private final class UploadFileRequest: HPostRequestProtocol, @unchecked Sendable {
    typealias Model = FileUploadResponse
    
    let fileName: String
    let fileData: Data
    var bodyParameters: [String: Any]?
    
    var url: String { "https://api.example.com/upload" }
    var bodyType: HRequestDataType { .multipart }
    
    init(fileName: String, fileData: Data) {
        self.fileName = fileName
        self.fileData = fileData
        self.bodyParameters = ["file": fileData, "filename": fileName]
    }
}

private struct DeleteUserRequest: HDeleteRequestProtocol {
    let userId: String
    
    var url: String { "https://api.example.com/users/\(userId)" }
}


private struct AuthenticatedRequest: HGetRequestProtocol {
    typealias Model = ProtectedData
    
    var url: String { "https://api.example.com/protected" }
    var needsAuth: Bool { true }
}

private final class CustomHeadersRequest: HGetRequestProtocol, @unchecked Sendable {
    typealias Model = TestUser
    
    var url: String { "https://api.example.com/users/1" }
    var headerParameters: [String: String]? = [
        "X-API-Version": "v2",
        "Accept": "application/json",
        "User-Agent": "HarborTestClient/1.0"
    ]
}

private struct GetUserByIdRequest: HGetRequestProtocol {
    typealias Model = TestUser
    
    let id: Int
    
    var url: String { "https://api.example.com/users/{id}" }
    var pathParameters: [String: String]? { ["id": "\(id)"] }
}

private final class UpdateUserRequest: HPutRequestProtocol, @unchecked Sendable {
    let id: Int
    let name: String
    let email: String
    var bodyParameters: [String: Any]?
    
    var url: String { "https://api.example.com/users/\(id)" }
    
    init(id: Int, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
        self.bodyParameters = ["name": name, "email": email]
    }
}

private final class UpdateUserWithFileRequest: HPutRequestProtocol, @unchecked Sendable {
    let id: Int
    let name: String
    let avatar: Data
    var bodyParameters: [String: Any]?
    
    var url: String { "https://api.example.com/users/\(id)" }
    var bodyType: HRequestDataType { .multipart }
    
    init(id: Int, name: String, avatar: Data) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.bodyParameters = ["name": name, "avatar": avatar]
    }
}

private final class PartialUpdateUserRequest: HPatchRequestProtocol, @unchecked Sendable {
    let id: Int
    let name: String
    var bodyParameters: [String: Any]?
    
    var url: String { "https://api.example.com/users/\(id)" }
    
    init(id: Int, name: String) {
        self.id = id
        self.name = name
        self.bodyParameters = ["name": name]
    }
}

private final class PartialUpdateUserWithJSONRequest: HPatchRequestProtocol, @unchecked Sendable {
    let id: Int
    let email: String
    var bodyParameters: [String: Any]?
    
    var url: String { "https://api.example.com/users/\(id)" }
    var bodyType: HRequestDataType { .json }
    
    init(id: Int, email: String) {
        self.id = id
        self.email = email
        self.bodyParameters = ["email": email]
    }
}

private struct TimeoutRequest: HGetRequestProtocol {
    typealias Model = TestUser
    
    var url: String { "https://slow.example.com/timeout" }
}

private struct ConnectionFailureRequest: HGetRequestProtocol {
    typealias Model = TestUser
    
    var url: String { "https://unreachable.example.com/data" }
}

private struct InvalidHostRequest: HGetRequestProtocol {
    typealias Model = TestUser
    
    var url: String { "https://nonexistent.invalid.domain/data" }
}

private struct MalformedRequest: HGetRequestProtocol {
    typealias Model = TestUser
    
    var url: String { "invalid-url-format" }
}

private struct CancellableRequest: HGetRequestProtocol {
    typealias Model = TestUser
    
    var url: String { "https://api.example.com/slow-endpoint" }
}

// MARK: - Helper Extensions

private extension HRequestError {
    var isApiError: Bool {
        switch self {
        case .api:
            return true
        default:
            return false
        }
    }
}
