# Harbor Protocol Guide

Complete guide to Harbor's protocol system for implementing HTTP requests.

## Protocol Overview

Harbor uses a hierarchy of protocols that compose different request capabilities. This guide explains when and how to use each protocol.

## Base Protocols

### HRequestBaseRequestProtocol

The foundation protocol that all requests must conform to.

**Location**: `Sources/Harbor/Request/HRequestProtocol.swift`

```swift
protocol HRequestBaseRequestProtocol {
    // Required
    var url: String { get }
    
    // Optional with defaults
    var headers: [String: String]? { get }
    var needsAuth: Bool { get }
    var cacheConfiguration: HCache.Configuration? { get }
    var retries: Int { get }
    var timeout: TimeInterval { get }
}
```

**Required Properties:**
- `url`: The endpoint URL (can include path parameters)

**Optional Properties (with defaults):**
- `headers`: Custom headers for this request (default: `nil`)
- `needsAuth`: Whether authentication is required (default: `false`)
- `cacheConfiguration`: Cache settings (default: `nil` - no caching)
- `retries`: Number of retry attempts (default: `0`)
- `timeout`: Request timeout in seconds (default: `60`)

### HRequestWithResultProtocol

For requests that return a decoded model.

```swift
protocol HRequestWithResultProtocol: HRequestBaseRequestProtocol {
    associatedtype Model: Decodable, Sendable
}
```

**Response Type**: `HResponseWithResult<Model>`

**When to Use:**
- Request returns JSON that should be decoded to a Swift type
- You need type-safe access to response data

### HRequestWithEmptyResponseProtocol

For requests that don't return meaningful data.

```swift
protocol HRequestWithEmptyResponseProtocol: HRequestBaseRequestProtocol {
}
```

**Response Type**: `HResponse` (only success/error status)

**When to Use:**
- DELETE requests that return 204 No Content
- Requests where you only care about success/failure
- Status check endpoints

## HTTP Method Protocols

### HGetRequestProtocol

**Purpose**: HTTP GET requests with optional caching

**Inherits**: `HRequestWithResultProtocol` or `HRequestWithEmptyResponseProtocol`

**Additional Properties:**
```swift
protocol HGetRequestProtocol {
    var queryParameters: [String: Any]? { get }
}
```

**Example - Basic GET:**
```swift
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/users/1"
}

let response = await GetUserRequest().request()
```

**Example - GET with Query Parameters:**
```swift
struct SearchUsersRequest: HGetRequestProtocol {
    typealias Model = [User]
    let url: String = "https://api.example.com/users"
    let queryParameters: [String: Any]? = ["search": "John", "limit": 10]
}

// Executes: GET https://api.example.com/users?search=John&limit=10
```

**Example - GET with Cache:**
```swift
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/users/1"
    let cacheConfiguration: HCache.Configuration? = .enabled(expirationTime: .oneHour)
}
```

**When to Use:**
- Retrieving resources from an API
- List/index endpoints
- Search endpoints
- Any idempotent read operation that can benefit from caching

### HPostRequestProtocol

**Purpose**: HTTP POST requests with request body

**Inherits**: `HRequestWithResultProtocol` or `HRequestWithEmptyResponseProtocol`

**Additional Properties:**
```swift
protocol HPostRequestProtocol {
    var bodyParameters: HBodyParameters? { get }
}
```

**Body Parameter Types:**

```swift
enum HBodyParameters {
    case json([String: Any])           // JSON body
    case multipart([HMultipartData])   // Multipart form data
}
```

**Example - POST with JSON:**
```swift
struct CreateUserRequest: HPostRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/users"
    let bodyParameters: HBodyParameters? = .json([
        "name": "John Doe",
        "email": "john@example.com",
        "age": 30
    ])
}
```

**Example - POST with Encodable Model:**
```swift
struct CreateUserRequest: HPostRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/users"
    
    let user: UserInput
    
    var bodyParameters: HBodyParameters? {
        guard let dict = user.asDictionary() else { return nil }
        return .json(dict)
    }
}
```

**Example - Multipart POST:**
```swift
struct UploadImageRequest: HPostRequestProtocol {
    typealias Model = ImageResponse
    let url: String = "https://api.example.com/images"
    
    let imageData: Data
    let description: String
    
    var bodyParameters: HBodyParameters? {
        let multipartData = [
            HMultipartData(
                data: imageData,
                name: "image",
                fileName: "photo.jpg",
                mimeType: "image/jpeg"
            ),
            HMultipartData(
                data: description.data(using: .utf8)!,
                name: "description",
                fileName: nil,
                mimeType: "text/plain"
            )
        ]
        return .multipart(multipartData)
    }
}
```

**When to Use:**
- Creating new resources
- Submitting form data
- Uploading files
- Non-idempotent operations

### HPutRequestProtocol

**Purpose**: HTTP PUT requests for full resource updates

**Inherits**: `HRequestWithResultProtocol` or `HRequestWithEmptyResponseProtocol`

**Additional Properties:**
```swift
protocol HPutRequestProtocol {
    var bodyParameters: HBodyParameters? { get }
}
```

**Example - Update User:**
```swift
struct UpdateUserRequest: HPutRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/users/1"
    let bodyParameters: HBodyParameters? = .json([
        "name": "Jane Doe",
        "email": "jane@example.com",
        "age": 28
    ])
}
```

**When to Use:**
- Replacing an entire resource
- Full updates (all fields required)
- Idempotent update operations

### HPatchRequestProtocol

**Purpose**: HTTP PATCH requests for partial resource updates

**Inherits**: `HRequestWithResultProtocol` or `HRequestWithEmptyResponseProtocol`

**Additional Properties:**
```swift
protocol HPatchRequestProtocol {
    var bodyParameters: HBodyParameters? { get }
}
```

**Example - Partial Update:**
```swift
struct UpdateUserEmailRequest: HPatchRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/users/1"
    let bodyParameters: HBodyParameters? = .json([
        "email": "newemail@example.com"
    ])
}
```

**When to Use:**
- Updating specific fields of a resource
- Partial updates (only changed fields)
- When PUT would require sending all fields

### HDeleteRequestProtocol

**Purpose**: HTTP DELETE requests for resource deletion

**Inherits**: Usually `HRequestWithEmptyResponseProtocol`

**No Additional Properties**

**Example - Delete Resource:**
```swift
struct DeleteUserRequest: HDeleteRequestProtocol, HRequestWithEmptyResponseProtocol {
    let url: String = "https://api.example.com/users/1"
}

let response = await DeleteUserRequest().request()
switch response {
case .success:
    print("User deleted successfully")
case .error(let error):
    print("Failed to delete: \(error)")
}
```

**Example - Delete with Response:**
```swift
struct DeleteUserRequest: HDeleteRequestProtocol {
    typealias Model = DeleteResponse
    let url: String = "https://api.example.com/users/1"
}
```

**When to Use:**
- Deleting resources
- Removing entries
- Cleanup operations

## JSON-RPC Protocol

### HJRPCRequestProtocol

**Purpose**: JSON-RPC 2.0 requests

**Location**: `Sources/HarborJRPC/Request/HJRPCRequestProtocol.swift`

**Required Properties:**
```swift
protocol HJRPCRequestProtocol {
    associatedtype Model: Decodable, Sendable
    var method: String { get }
    var params: [String: Any]? { get }
}
```

**Example - Simple JSON-RPC:**
```swift
struct GetBlockNumberRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "eth_blockNumber"
    let params: [String: Any]? = nil
}

// Configure JSON-RPC endpoint once
await HarborJRPC.setURL("https://ethereum.publicnode.com")

// Execute request
let response = await GetBlockNumberRequest().request()
```

**Example - JSON-RPC with Parameters:**
```swift
struct GetBalanceRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "eth_getBalance"
    let params: [String: Any]?
    
    init(address: String, block: String = "latest") {
        self.params = ["address": address, "block": block]
    }
}
```

**Response Format:**
```swift
enum HJRPCResponse<Model: Decodable> {
    case success(result: Model)
    case error(code: Int, message: String)
}
```

**When to Use:**
- Blockchain RPC calls (Ethereum, Bitcoin, etc.)
- JSON-RPC APIs
- Remote procedure call interfaces

## Protocol Composition

### Combining Protocols

You can conform to multiple protocols for additional functionality:

**With Debug:**
```swift
struct MyRequest: HGetRequestProtocol, HDebugRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/user"
    var debugType: HDebugRequestType = .requestAndResponse
}
```

**Debug Types:**
```swift
enum HDebugRequestType {
    case request          // Log request only
    case response         // Log response only
    case requestAndResponse  // Log both
}
```

**Output**: Generates cURL command and logs response data

### Creating Reusable Base Requests

**Pattern 1: Protocol Extension**
```swift
protocol MyAPIRequest: HGetRequestProtocol {
    var endpoint: String { get }
}

extension MyAPIRequest {
    var url: String { "https://api.myapp.com/\(endpoint)" }
    var needsAuth: Bool { true }
    var headers: [String: String]? { ["X-API-Version": "2.0"] }
}

// Usage
struct GetUserRequest: MyAPIRequest {
    typealias Model = User
    let endpoint = "users/1"
}
```

**Pattern 2: Generic Base Class**
```swift
class BaseAPIRequest<T: Decodable & Sendable>: HGetRequestProtocol, @unchecked Sendable {
    typealias Model = T
    
    let endpoint: String
    var url: String { "https://api.myapp.com/\(endpoint)" }
    let needsAuth: Bool = true
    
    init(endpoint: String) {
        self.endpoint = endpoint
    }
}

// Usage
let request = BaseAPIRequest<User>(endpoint: "users/1")
```

## Advanced Features

### Dynamic URLs

```swift
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let userId: String
    var url: String { "https://api.example.com/users/\(userId)" }
}

let request = GetUserRequest(userId: "123")
```

### Conditional Properties

```swift
struct SearchRequest: HGetRequestProtocol {
    typealias Model = [Result]
    let url = "https://api.example.com/search"
    let searchTerm: String?
    let includeArchived: Bool
    
    var queryParameters: [String: Any]? {
        var params: [String: Any] = [:]
        if let term = searchTerm {
            params["q"] = term
        }
        if includeArchived {
            params["archived"] = true
        }
        return params.isEmpty ? nil : params
    }
}
```

### Retry Configuration

```swift
struct ReliableRequest: HGetRequestProtocol {
    typealias Model = Data
    let url = "https://api.example.com/data"
    let retries: Int = 3  // Will retry up to 3 times on failure
}
```

### Custom Timeout

```swift
struct LongRunningRequest: HPostRequestProtocol {
    typealias Model = Result
    let url = "https://api.example.com/process"
    let timeout: TimeInterval = 180  // 3 minutes
    let bodyParameters: HBodyParameters? = .json(["data": "..."])
}
```

### Request Authentication

```swift
struct AuthenticatedRequest: HGetRequestProtocol {
    typealias Model = PrivateData
    let url = "https://api.example.com/private"
    let needsAuth: Bool = true  // Will use configured HAuthProviderProtocol
}
```

## Response Types

### HResponse (Empty Response)

```swift
enum HResponse {
    case success
    case error(HRequestError)
}
```

**Usage:**
```swift
let response = await deleteRequest.request()
switch response {
case .success:
    print("Success")
case .error(let error):
    print("Error: \(error)")
}
```

### HResponseWithResult<Model>

```swift
enum HResponseWithResult<Model> {
    case success(result: Model)
    case error(HRequestError)
}
```

**Usage:**
```swift
let response = await getRequest.request()
switch response {
case .success(let user):
    print("User: \(user.name)")
case .error(let error):
    print("Error: \(error)")
}
```

### Error Handling

```swift
enum HRequestError: Error {
    case authNeeded
    case noConnectionError
    case invalidURL
    case invalidResponse
    case decodingError(Error)
    case serverError(statusCode: Int, data: Data?)
    case cancelled
    case timeout
    case unknown(Error)
}
```

**Detailed Error Handling:**
```swift
let response = await request.request()
switch response {
case .success(let data):
    // Handle success
case .error(let error):
    switch error {
    case .authNeeded:
        // Re-authenticate user
    case .noConnectionError:
        // Show offline message
    case .decodingError(let decodingError):
        // Log decoding issue
    case .serverError(let statusCode, _):
        // Handle specific HTTP errors
        if statusCode == 404 {
            // Not found
        }
    case .timeout:
        // Retry or show timeout message
    default:
        // Generic error handling
    }
}
```

## Best Practices

### 1. Use Structs When Possible

```swift
// Preferred: struct is implicitly Sendable
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url: String
}
```

### 2. Make Requests Reusable

```swift
// Good: Parameterized request
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let userId: String
    var url: String { "https://api.example.com/users/\(userId)" }
}

// Usage
let request1 = GetUserRequest(userId: "123")
let request2 = GetUserRequest(userId: "456")
```

### 3. Group Related Requests

```swift
enum UserAPI {
    struct Get: HGetRequestProtocol {
        typealias Model = User
        let userId: String
        var url: String { "https://api.example.com/users/\(userId)" }
    }
    
    struct Create: HPostRequestProtocol {
        typealias Model = User
        let url = "https://api.example.com/users"
        let bodyParameters: HBodyParameters?
    }
    
    struct Update: HPutRequestProtocol {
        typealias Model = User
        let userId: String
        var url: String { "https://api.example.com/users/\(userId)" }
        let bodyParameters: HBodyParameters?
    }
    
    struct Delete: HDeleteRequestProtocol, HRequestWithEmptyResponseProtocol {
        let userId: String
        var url: String { "https://api.example.com/users/\(userId)" }
    }
}

// Usage
let user = await UserAPI.Get(userId: "123").request()
await UserAPI.Delete(userId: "123").request()
```

### 4. Cache Appropriately

```swift
// Cache static data
struct GetCountriesRequest: HGetRequestProtocol {
    typealias Model = [Country]
    let url = "https://api.example.com/countries"
    let cacheConfiguration: HCache.Configuration? = .enabled(expirationTime: .oneWeek)
}

// Don't cache dynamic data
struct GetUserBalanceRequest: HGetRequestProtocol {
    typealias Model = Balance
    let url = "https://api.example.com/balance"
    let cacheConfiguration: HCache.Configuration? = nil  // Always fetch fresh
}
```

### 5. Type-Safe Models

```swift
// Define proper Codable models
struct User: Codable, Sendable {
    let id: Int
    let name: String
    let email: String
}

struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User  // Type-safe response
    let url: String
}
```

## Quick Reference

| Protocol | HTTP Method | Body | Response | Cache Support | Common Use |
|----------|-------------|------|----------|---------------|------------|
| `HGetRequestProtocol` | GET | ❌ | ✅ | ✅ | Fetch data |
| `HPostRequestProtocol` | POST | ✅ | ✅ | ❌ | Create resource |
| `HPutRequestProtocol` | PUT | ✅ | ✅ | ❌ | Full update |
| `HPatchRequestProtocol` | PATCH | ✅ | ✅ | ❌ | Partial update |
| `HDeleteRequestProtocol` | DELETE | ❌ | ✅/❌ | ❌ | Delete resource |
| `HJRPCRequestProtocol` | POST | ✅ | ✅ | ❌ | JSON-RPC calls |

## Related Files

**Protocol Definitions:**
- `Sources/Harbor/Request/HRequestProtocol.swift`
- `Sources/HarborJRPC/Request/HJRPCRequestProtocol.swift`

**Examples:**
- `Example/HarborExample/Requests/RESTRequest.swift` - GET example
- `Example/HarborExample/Requests/JRPCRequest.swift` - JSON-RPC example
- `Tests/HarborTests/Mocks/MocksRequest.swift` - Various protocol implementations
