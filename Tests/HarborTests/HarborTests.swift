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
        
        let mock = HMock(request: GetUserRequest.self, statusCode: 200, jsonResponse: jsonString)
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
        
        let mock = HMock(request: GetUsersRequest.self, statusCode: 200, jsonResponse: jsonString)
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
        let mock = HMock(request: CreateUserRequest.self, statusCode: 201)
        await Harbor.register(mock: mock)
        
        // When
        let request = CreateUserRequest(name: "New User", email: "new@example.com")
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
            XCTAssertNotNil(urlRequest.url) // Verified by URLBuilder
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    func testPostRequestWithMultipart() async throws {
        // Given
        let mock = HMock(request: UploadFileRequest.self, statusCode: 200)
        await Harbor.register(mock: mock)
        
        // When
        let request = UploadFileRequest(fileName: "test.jpg", fileData: Data("test".utf8))
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
            XCTAssertNotNil(urlRequest.url) // Verified by URLBuilder
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    // MARK: - DELETE Request Tests
    
    func testDeleteRequestExecution() async throws {
        // Given
        let mock = HMock(request: DeleteUserRequest.self, statusCode: 204)
        await Harbor.register(mock: mock)
        
        // When
        let request = DeleteUserRequest(userId: "1")
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
            XCTAssertNotNil(urlRequest.url) // Verified by URLBuilder
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
        
        let mock = HMock(request: AuthenticatedRequest.self, statusCode: 200, jsonResponse: jsonString)
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
        let mock = HMock(request: AuthenticatedRequest.self, statusCode: 401, error: .authNeeded)
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
                let count = await HMocker.callCount(for: type(of: request))
                XCTAssertEqual(count, 1) // Expected auth error
            default:
                XCTFail("Expected authNeeded but got: \(error)")
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testNetworkErrorHandling() async throws {
        // Given
        let mock = HMock(request: GetUserRequest.self, statusCode: 500, error: .noConnection)
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
                let count = await HMocker.callCount(for: type(of: request))
                XCTAssertEqual(count, 1) // Expected network error
            default:
                XCTFail("Expected noConnection but got: \(error)")
            }
        }
    }
    
    func testAPIErrorHandling() async throws {
        // Given
        let mock = HMock(request: GetUserRequest.self, statusCode: 404)
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
        let mock = HMock(request: GetUserRequest.self, statusCode: 200, jsonResponse: "invalid-json")
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
                let count = await HMocker.callCount(for: type(of: request))
                XCTAssertEqual(count, 1)
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
        
        let mock = HMock(request: CustomHeadersRequest.self, statusCode: 200, jsonResponse: jsonString)
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
        let mock = HMock(request: TimeoutRequest.self, statusCode: 408, error: .timeout)
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
                let count = await HMocker.callCount(for: type(of: request))
                XCTAssertEqual(count, 1) // Expected timeout error
            default:
                XCTFail("Expected timeout error but got: \(error)")
            }
        }
    }
    
    func testConnectionFailure() async throws {
        // Given
        let mock = HMock(request: ConnectionFailureRequest.self, statusCode: 0, error: .noConnection)
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
                let count = await HMocker.callCount(for: type(of: request))
                XCTAssertEqual(count, 1) // Expected connection error
            default:
                XCTFail("Expected connection error but got: \(error)")
            }
        }
    }
    
    func testCannotFindHost() async throws {
        // Given
        let mock = HMock(request: InvalidHostRequest.self, statusCode: 0, error: .cannotFindHost)
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
                let count = await HMocker.callCount(for: type(of: request))
                XCTAssertEqual(count, 1) // Expected host not found error
            default:
                XCTFail("Expected host not found error but got: \(error)")
            }
        }
    }
    
    func testMalformedRequest() async throws {
        // Given
        let mock = HMock(request: MalformedRequest.self, statusCode: 400, error: .malformedRequest())
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
                let count = await HMocker.callCount(for: type(of: request))
                XCTAssertEqual(count, 1) // Expected malformed request error
            default:
                XCTFail("Expected malformed request error but got: \(error)")
            }
        }
    }
    
    func testRequestCancellation() async throws {
        // Given a mock that delays its response, giving the consumer a window to cancel
        let mock = HMock(request: CancellableRequest.self, statusCode: 200, jsonResponse: "{\"data\": \"slow response\"}", delay: 2.0)
        await Harbor.register(mock: mock)

        // When the request is cancelled while still waiting for the delayed mock
        let task = Task<HResponseWithResult<TestUser>, Never> {
            let request = CancellableRequest()
            return await request.request()
        }

        // Let the request reach the in-flight delay before cancelling.
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let response = await task.value

        // Then the result surfaces a cancellation error rather than succeeding.
        guard case .error(let error) = response, case .cancelled = error else {
            XCTFail("Expected .cancelled but got: \(response)")
            return
        }
    }
    
    // MARK: - Path Parameters Tests
    
    func testPathParameters() async throws {
        // Given
        let user = TestUser(id: 123, name: "John", email: "john@example.com")
        let jsonData = try JSONEncoder().encode(user)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        let mock = HMock(request: GetUserByIdRequest.self, statusCode: 200, jsonResponse: jsonString)
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
        let mock = HMock(request: UpdateUserRequest.self, statusCode: 200)
        await Harbor.register(mock: mock)
        
        // When
        let request = UpdateUserRequest(id: 1, name: "Updated User", email: "updated@example.com")
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
            XCTAssertNotNil(urlRequest.url) // Verified by URLBuilder
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    func testPutRequestWithMultipart() async throws {
        // Given
        let mock = HMock(request: UpdateUserWithFileRequest.self, statusCode: 200)
        await Harbor.register(mock: mock)
        
        // When
        let request = UpdateUserWithFileRequest(id: 1, name: "Updated User", avatar: Data("avatar".utf8))
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
            XCTAssertNotNil(urlRequest.url) // Verified by URLBuilder
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    // MARK: - PATCH Request Tests
    
    func testPatchRequestExecution() async throws {
        // Given
        let mock = HMock(request: PartialUpdateUserRequest.self, statusCode: 200)
        await Harbor.register(mock: mock)
        
        // When
        let request = PartialUpdateUserRequest(id: 1, name: "Partially Updated")
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
            XCTAssertNotNil(urlRequest.url) // Verified by URLBuilder
        case .error(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    func testPatchRequestWithJSONBody() async throws {
        // Given
        let mock = HMock(request: PartialUpdateUserWithJSONRequest.self, statusCode: 200)
        await Harbor.register(mock: mock)
        
        // When
        let request = PartialUpdateUserWithJSONRequest(id: 1, email: "newemail@example.com")
        let response = await request.request()
        
        // Then
        switch response {
        case .success:
            let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
            XCTAssertNotNil(urlRequest.url) // Verified by URLBuilder
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

private struct CreateUserRequest: HPostRequestProtocol, @unchecked Sendable {
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

private struct UploadFileRequest: HPostRequestProtocol, @unchecked Sendable {
    typealias Model = FileUploadResponse
    
    let fileName: String
    let fileData: Data
    var bodyParameters: [String: Any]? = nil
    var multipartBody: [String: HFormValue]?
    
    var url: String { "https://api.example.com/upload" }
    
    init(fileName: String, fileData: Data) {
        self.fileName = fileName
        self.fileData = fileData
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? fileData.write(to: fileURL)
        self.multipartBody = ["file": .file(url: fileURL, mimeType: nil, fileName: fileName), "filename": .text(fileName)]
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

private struct CustomHeadersRequest: HGetRequestProtocol {
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

private struct UpdateUserRequest: HPutRequestProtocol, @unchecked Sendable {
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

private struct UpdateUserWithFileRequest: HPutRequestProtocol, @unchecked Sendable {
    typealias Model = TestUser
    
    let id: Int
    let name: String
    let fileData: Data
    var bodyParameters: [String: Any]? = nil
    var multipartBody: [String: HFormValue]?
    
    var url: String { "https://api.example.com/users/\(id)" }
    
    init(id: Int, name: String, avatar: Data) {
        self.id = id
        self.name = name
        self.fileData = avatar
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("avatar.jpg")
        try? fileData.write(to: fileURL)
        self.multipartBody = ["name": .text(name), "avatar": .file(url: fileURL, mimeType: nil, fileName: "avatar.jpg")]
    }
}

private struct PartialUpdateUserRequest: HPatchRequestProtocol, @unchecked Sendable {
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

private struct PartialUpdateUserWithJSONRequest: HPatchRequestProtocol, @unchecked Sendable {
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
