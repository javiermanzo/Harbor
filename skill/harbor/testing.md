# Harbor Testing Guide

Complete guide to testing with Harbor's mock system and best practices.

## Overview

Harbor provides a comprehensive mocking system that allows you to test network requests without making actual HTTP calls. This is essential for:

- **Fast test execution**: No network latency
- **Deterministic tests**: Consistent, repeatable results
- **Offline testing**: No internet connection required
- **Edge case testing**: Easily simulate errors and edge cases

**Location**: `Sources/Harbor/Mock/`

## Mock System

### HMock

**Location**: `Sources/Harbor/Mock/HMock.swift`

```swift
struct HMock<Request: HRequestBaseRequestProtocol>: Sendable {
    let requestType: Request.Type
    let statusCode: Int
    let jsonResponse: String?
    let data: Data?
    let delay: TimeInterval
    let error: HRequestError?
}
```

### HMocker

**Location**: `Sources/Harbor/Mock/HMocker.swift`

```swift
@HRequestManagerActor
final class HMocker {
    static var mocks: [String: Any] = [:]
    static var mocksOnlyInDebug: Bool = true
}
```

## Creating Mocks

### Basic Mock with JSON

```swift
// Define a mock response
let mockJSON = """
{
    "id": 1,
    "name": "John Doe",
    "email": "john@example.com"
}
"""

let mock = await HMock(
    request: GetUserRequest.self,
    statusCode: 200,
    jsonResponse: mockJSON
)

// Register the mock
await Harbor.register(mock: mock)
```

### Mock with Encodable Model

```swift
let mockUser = User(id: 1, name: "John Doe", email: "john@example.com")
let jsonData = try JSONEncoder().encode(mockUser)
let jsonString = String(data: jsonData, encoding: .utf8)!

let mock = await HMock(
    request: GetUserRequest.self,
    statusCode: 200,
    jsonResponse: jsonString
)

await Harbor.register(mock: mock)
```

### Mock with Data

```swift
// For non-JSON responses
let imageData = UIImage(named: "test-image")?.pngData()

let mock = await HMock(
    request: GetImageRequest.self,
    statusCode: 200,
    data: imageData
)

await Harbor.register(mock: mock)
```

### Mock with Error

```swift
// Simulate network error
let mock = await HMock(
    request: GetUserRequest.self,
    error: .noConnection
)

await Harbor.register(mock: mock)
```

### Mock with Delay

```swift
// Simulate slow network
let mock = await HMock(
    request: GetUserRequest.self,
    statusCode: 200,
    jsonResponse: mockJSON,
    delay: 2.0  // 2 second delay
)

await Harbor.register(mock: mock)
```

### Mock HTTP Errors

```swift
// 404 Not Found
let mock404 = await HMock(
    request: GetUserRequest.self,
    statusCode: 404,
    jsonResponse: """
    {
        "error": "User not found"
    }
    """
)

// 500 Server Error
let mock500 = await HMock(
    request: GetUserRequest.self,
    statusCode: 500,
    jsonResponse: """
    {
        "error": "Internal server error"
    }
    """
)

// 401 Unauthorized
let mock401 = await HMock(
    request: GetUserRequest.self,
    statusCode: 401,
    jsonResponse: """
    {
        "error": "Unauthorized"
    }
    """
)
```

## Mock Management

### Register Mock

```swift
await Harbor.register(mock: mock)
```

### Remove Specific Mock

```swift
await Harbor.remove(mock: GetUserRequest.self)
```

### Remove All Mocks

```swift
await Harbor.removeAllMocks()
```

### Mock Scope Configuration

```swift
// Mocks only work in DEBUG builds (default)
await Harbor.setMocksOnlyInDebug(true)

// Mocks work in all builds (for testing)
await Harbor.setMocksOnlyInDebug(false)
```

## Test Structure

### Given-When-Then Pattern

Harbor tests follow the Given-When-Then structure for clarity:

```swift
func testGetUserRequest() async throws {
    // Given: Setup test conditions
    let mockUser = User(id: 1, name: "John Doe", email: "john@example.com")
    let jsonData = try JSONEncoder().encode(mockUser)
    let jsonString = String(data: jsonData, encoding: .utf8)!
    
    let mock = await HMock(
        request: GetUserRequest.self,
        statusCode: 200,
        jsonResponse: jsonString
    )
    await Harbor.register(mock: mock)
    
    // When: Execute the action
    let request = GetUserRequest(userId: "1")
    let response = await request.request()
    
    // Then: Verify the result
    switch response {
    case .success(let user):
        XCTAssertEqual(user.id, 1)
        XCTAssertEqual(user.name, "John Doe")
        XCTAssertEqual(user.email, "john@example.com")
    case .error(let error):
        XCTFail("Expected success but got error: \(error)")
    }
}
```

### Setup and Teardown

```swift
final class HarborTests: XCTestCase {
    override func setUp() async throws {
        await super.setUp()
        
        // Clean state before each test
        await Harbor.removeAllMocks()
        await Harbor.clearAllCache()
        await Harbor.setMocksOnlyInDebug(false)
        await Harbor.setAuthProvider(nil)
        await Harbor.setDefaultCacheType(.disabled)
    }
    
    override func tearDown() async throws {
        // Clean up after each test
        await Harbor.removeAllMocks()
        await Harbor.clearAllCache()
        
        await super.tearDown()
    }
    
    func testSomething() async throws {
        // Test code
    }
}
```

## Testing Different Request Types

### GET Request Test

```swift
func testGetRequest() async throws {
    // Given
    let mockJSON = """
    {
        "id": 123,
        "title": "Test Post",
        "body": "This is a test"
    }
    """
    
    let mock = await HMock(
        request: GetPostRequest.self,
        statusCode: 200,
        jsonResponse: mockJSON
    )
    await Harbor.register(mock: mock)
    
    // When
    let request = GetPostRequest(postId: "123")
    let response = await request.request()
    
    // Then
    switch response {
    case .success(let post):
        XCTAssertEqual(post.id, 123)
        XCTAssertEqual(post.title, "Test Post")
    case .error(let error):
        XCTFail("Request failed: \(error)")
    }
}
```

### POST Request Test

```swift
func testPostRequest() async throws {
    // Given
    let mockJSON = """
    {
        "id": 456,
        "name": "New User",
        "created": true
    }
    """
    
    let mock = await HMock(
        request: CreateUserRequest.self,
        statusCode: 201,
        jsonResponse: mockJSON
    )
    await Harbor.register(mock: mock)
    
    // When
    let request = CreateUserRequest(name: "New User", email: "new@example.com")
    let response = await request.request()
    
    // Then
    switch response {
    case .success(let result):
        XCTAssertEqual(result.id, 456)
        XCTAssertTrue(result.created)
    case .error(let error):
        XCTFail("Request failed: \(error)")
    }
}
```

### DELETE Request Test

```swift
func testDeleteRequest() async throws {
    // Given
    let mock = await HMock(
        request: DeleteUserRequest.self,
        statusCode: 204,
        jsonResponse: nil
    )
    await Harbor.register(mock: mock)
    
    // When
    let request = DeleteUserRequest(userId: "123")
    let response = await request.request()
    
    // Then
    switch response {
    case .success:
        XCTAssertTrue(true, "Delete succeeded")
    case .error(let error):
        XCTFail("Delete failed: \(error)")
    }
}
```

## Testing Error Cases

### Network Error Test

```swift
func testNetworkError() async throws {
    // Given
    let mock = await HMock(
        request: GetUserRequest.self,
        error: .noConnection
    )
    await Harbor.register(mock: mock)
    
    // When
    let response = await GetUserRequest(userId: "1").request()
    
    // Then
    switch response {
    case .success:
        XCTFail("Expected error but got success")
    case .error(let error):
        XCTAssertEqual(error, .noConnection)
    }
}
```

### HTTP Error Test

```swift
func testHTTPError() async throws {
    // Given
    let errorJSON = """
    {
        "error": "User not found",
        "code": "USER_NOT_FOUND"
    }
    """
    
    let mock = await HMock(
        request: GetUserRequest.self,
        statusCode: 404,
        jsonResponse: errorJSON
    )
    await Harbor.register(mock: mock)
    
    // When
    let response = await GetUserRequest(userId: "999").request()
    
    // Then
    switch response {
    case .success:
        XCTFail("Expected error but got success")
    case .error(let error):
        if case .api(let statusCode, _) = error {
            XCTAssertEqual(statusCode, 404)
        } else {
            XCTFail("Expected api error but got \(error)")
        }
    }
}
```

### Authentication Error Test

```swift
func testAuthenticationError() async throws {
    // Given
    let mock = await HMock(
        request: GetPrivateDataRequest.self,
        statusCode: 401,
        jsonResponse: """
        {
            "error": "Unauthorized"
        }
        """
    )
    await Harbor.register(mock: mock)
    
    // When
    let response = await GetPrivateDataRequest().request()
    
    // Then
    switch response {
    case .success:
        XCTFail("Expected auth error")
    case .error(let error):
        if case .api(let statusCode, _) = error {
            XCTAssertEqual(statusCode, 401)
        } else {
            XCTFail("Expected 401 error")
        }
    }
}
```

### Timeout Test

```swift
func testTimeout() async throws {
    // Given
    let mock = await HMock(
        request: GetUserRequest.self,
        error: .timeout
    )
    await Harbor.register(mock: mock)
    
    // When
    let response = await GetUserRequest(userId: "1").request()
    
    // Then
    switch response {
    case .success:
        XCTFail("Expected timeout error")
    case .error(let error):
        XCTAssertEqual(error, .timeout)
    }
}
```

## Testing Cache

### Cache Hit Test

```swift
func testCacheHit() async throws {
    // Given
    let mockJSON = """
    {
        "id": 1,
        "name": "Cached User"
    }
    """
    
    let mock = await HMock(
        request: GetUserRequest.self,
        statusCode: 200,
        jsonResponse: mockJSON
    )
    await Harbor.register(mock: mock)
    
    let request = GetUserRequest(userId: "1")
    
    // First request - populates cache
    _ = await request.request()
    
    // When - Second request should use cache
    let cachedUser = await request.cache()
    
    // Then
    XCTAssertNotNil(cachedUser)
    XCTAssertEqual(cachedUser?.name, "Cached User")
}
```

### Cache Expiration Test

```swift
func testCacheExpiration() async throws {
    // Given
    await Harbor.setDefaultCacheType(.custom(HCache.Configuration(expirationTime: 1.0)))
    
    let mockJSON = """
    {
        "id": 1,
        "name": "User"
    }
    """
    
    let mock = await HMock(
        request: GetUserRequest.self,
        statusCode: 200,
        jsonResponse: mockJSON
    )
    await Harbor.register(mock: mock)
    
    let request = GetUserRequest(userId: "1")
    
    // First request
    _ = await request.request()
    
    // Cache should exist
    XCTAssertNotNil(await request.cache())
    
    // Wait for expiration
    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
    
    // Cache should be expired
    XCTAssertNil(await request.cache())
}
```

### Cache Clear Test

```swift
func testCacheClear() async throws {
    // Given
    let mockJSON = """{"id": 1, "name": "User"}"""
    
    let mock = await HMock(
        request: GetUserRequest.self,
        statusCode: 200,
        jsonResponse: mockJSON
    )
    await Harbor.register(mock: mock)
    
    let request = GetUserRequest(userId: "1")
    
    // Populate cache
    _ = await request.request()
    XCTAssertNotNil(await request.cache())
    
    // When
    await request.clearCache()
    
    // Then
    XCTAssertNil(await request.cache())
}
```

## Testing Streaming

### Stream Test

```swift
func testRequestStream() async throws {
    // Given
    let mockJSON = """
    {
        "id": 1,
        "name": "User"
    }
    """
    
    let mock = await HMock(
        request: GetUserRequest.self,
        statusCode: 200,
        jsonResponse: mockJSON
    )
    await Harbor.register(mock: mock)
    
    let request = GetUserRequest(userId: "1")
    
    // When
    var emissions: [(User, HOriginType)] = []
    for try await (user, origin) in request.requestStream(source: .cacheAndRemote) {
        emissions.append((user, origin))
    }
    
    // Then
    // First emission from network (no cache yet)
    XCTAssertEqual(emissions.count, 1)
    XCTAssertEqual(emissions[0].0.name, "User")
    XCTAssertEqual(emissions[0].1, .remote)
}
```

## Testing Authentication

### Mock Auth Provider

```swift
final class MockAuthProvider: HAuthProviderProtocol, @unchecked Sendable {
    var token: String?
    var expired: Bool = false
    var refreshCalled: Bool = false
    
    func getHeaders() async -> [String: String] {
        guard let token = token else {
            return [:]
        }
        return ["Authorization": "Bearer \(token)"]
    }
    
    func isTokenExpired() async -> Bool {
        return expired
    }
    
    func refreshToken() async throws {
        refreshCalled = true
        token = "refreshed-token"
        expired = false
    }
}
```

### Auth Test

```swift
func testAuthenticatedRequest() async throws {
    // Given
    let mockAuth = MockAuthProvider()
    mockAuth.token = "test-token"
    await Harbor.setAuthProvider(mockAuth)
    
    let mockJSON = """{"data": "private"}"""
    let mock = await HMock(
        request: GetPrivateDataRequest.self,
        statusCode: 200,
        jsonResponse: mockJSON
    )
    await Harbor.register(mock: mock)
    
    // When
    let response = await GetPrivateDataRequest().request()
    
    // Then
    switch response {
    case .success(let data):
        XCTAssertEqual(data.data, "private")
    case .error(let error):
        XCTFail("Request failed: \(error)")
    }
}
```

### Token Refresh Test

```swift
func testTokenRefresh() async throws {
    // Given
    let mockAuth = MockAuthProvider()
    mockAuth.token = "old-token"
    mockAuth.expired = true
    await Harbor.setAuthProvider(mockAuth)
    
    let mockJSON = """{"data": "private"}"""
    let mock = await HMock(
        request: GetPrivateDataRequest.self,
        statusCode: 200,
        jsonResponse: mockJSON
    )
    await Harbor.register(mock: mock)
    
    // When
    _ = await GetPrivateDataRequest().request()
    
    // Then
    XCTAssertTrue(mockAuth.refreshCalled)
    XCTAssertEqual(mockAuth.token, "refreshed-token")
}
```

## Testing JSON-RPC

### JSON-RPC Mock

```swift
func testJRPCRequest() async throws {
    // Given
    let mockJSON = """
    {
        "jsonrpc": "2.0",
        "id": 1,
        "result": "0x1234567"
    }
    """
    
    let mock = await HMock(
        request: GetBlockNumberRequest.self,
        statusCode: 200,
        jsonResponse: mockJSON
    )
    await Harbor.register(mock: mock)
    
    // When
    let response = await GetBlockNumberRequest().request()
    
    // Then
    switch response {
    case .success(let blockNumber):
        XCTAssertEqual(blockNumber, "0x1234567")
    case .error(let error):
        XCTFail("Request failed: \(error)")
    }
}
```

### JSON-RPC Error Mock

```swift
func testJRPCError() async throws {
    // Given
    let mockJSON = """
    {
        "jsonrpc": "2.0",
        "id": 1,
        "error": {
            "code": -32600,
            "message": "Invalid Request"
        }
    }
    """
    
    let mock = await HMock(
        request: GetBlockNumberRequest.self,
        statusCode: 200,
        jsonResponse: mockJSON
    )
    await Harbor.register(mock: mock)
    
    // When
    let response = await GetBlockNumberRequest().request()
    
    // Then
    switch response {
    case .success:
        XCTFail("Expected error but got success")
    case .error:
        XCTAssertTrue(true)
    }
}
```

## Best Practices

### 1. Clean State Between Tests

```swift
override func setUp() async throws {
    await Harbor.removeAllMocks()
    await Harbor.clearAllCache()
    await Harbor.setAuthProvider(nil)
}
```

### 2. Use Descriptive Mock Data

```swift
// Good: Clear and realistic
let mockUser = """
{
    "id": 1,
    "name": "John Doe",
    "email": "john@example.com",
    "verified": true
}
"""

// Bad: Minimal and unclear
let mockUser = """{"id": 1}"""
```

### 3. Test Both Success and Failure

```swift
func testGetUserSuccess() async throws {
    // Test success case
}

func testGetUserNotFound() async throws {
    // Test 404 error
}

func testGetUserNetworkError() async throws {
    // Test network error
}
```

### 4. Use Type-Safe Assertions

```swift
// Good: Type-safe error checking
if case .api(let statusCode, _) = error {
    XCTAssertEqual(statusCode, 404)
}

// Less ideal: Generic error check
XCTAssertNotNil(error)
```

### 5. Test Edge Cases

```swift
func testEmptyResponse() async throws {
    let mock = await HMock(
        request: GetListRequest.self,
        statusCode: 200,
        jsonResponse: "[]"
    )
    // Test empty array handling
}

func testLargeResponse() async throws {
    // Test with large JSON payload
}

func testSpecialCharacters() async throws {
    // Test with unicode, emojis, etc.
}
```

### 6. Isolate Tests

```swift
// Each test should be independent
func testA() async throws {
    // Setup specific to test A
    // Execute test A
    // No dependency on test B
}

func testB() async throws {
    // Setup specific to test B
    // Execute test B
    // No dependency on test A
}
```

### 7. Use Reusable Mock Factories

```swift
extension HMock {
    static func successUser() async -> HMock<GetUserRequest> {
        let json = """{"id": 1, "name": "Test User"}"""
        return await HMock(
            request: GetUserRequest.self,
            statusCode: 200,
            jsonResponse: json
        )
    }
    
    static func notFoundUser() async -> HMock<GetUserRequest> {
        return await HMock(
            request: GetUserRequest.self,
            statusCode: 404,
            jsonResponse: """{"error": "Not found"}"""
        )
    }
}

// Usage
func testUser() async throws {
    await Harbor.register(mock: .successUser())
    // Test
}
```

## Performance Testing

### Test with Delays

```swift
func testSlowNetwork() async throws {
    let mock = await HMock(
        request: GetUserRequest.self,
        statusCode: 200,
        jsonResponse: mockJSON,
        delay: 3.0  // Simulate 3 second delay
    )
    await Harbor.register(mock: mock)
    
    let start = Date()
    _ = await GetUserRequest(userId: "1").request()
    let duration = Date().timeIntervalSince(start)
    
    XCTAssertGreaterThanOrEqual(duration, 3.0)
}
```

### Test Concurrent Requests

```swift
func testConcurrentRequests() async throws {
    let mock = await HMock(
        request: GetUserRequest.self,
        statusCode: 200,
        jsonResponse: mockJSON
    )
    await Harbor.register(mock: mock)
    
    // Execute 10 concurrent requests
    await withTaskGroup(of: Void.self) { group in
        for i in 1...10 {
            group.addTask {
                let response = await GetUserRequest(userId: "\(i)").request()
                XCTAssertTrue(response.isSuccess)
            }
        }
    }
}
```

## Related Files

**Mock Implementation:**
- `Sources/Harbor/Mock/HMocker.swift` - Mock registry
- `Sources/Harbor/Mock/HMock.swift` - Mock definition

**Test Examples:**
- `Tests/HarborTests/HarborTests.swift` - Integration tests
- `Tests/HarborTests/HarborCacheTests.swift` - Cache tests
- `Tests/HarborTests/HarborStreamTests.swift` - Streaming tests
- `Tests/HarborTests/HarborSecurityTests.swift` - Security tests
- `Tests/HarborTests/Mocks/MocksRequest.swift` - Reusable mock requests
