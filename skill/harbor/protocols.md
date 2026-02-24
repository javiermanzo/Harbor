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
    var headerParameters: [String: String]? { get set }
    var needsAuth: Bool { get }
    var cacheType: HCache.CacheType? { get }
    var retries: Int { get }
    var timeoutInterval: TimeInterval? { get }
}
```

**Required Properties:**
- `url`: The endpoint URL (can include path parameters)

**Optional Properties (with defaults):**
- `headerParameters`: Custom headers for this request (default: `nil`)
- `needsAuth`: Whether authentication is required (default: `false`)
- `cacheType`: Cache settings (default: `nil` - uses global default)
- `retries`: Number of retry attempts (default: `nil`)
- `timeoutInterval`: Request timeout in seconds (default: `nil` - uses global config, default global is 15s)

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
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneHour))
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
    var bodyParameters: [String: Any]? { get }
    var bodyType: HRequestDataType { get }
}
```

**Example - POST with JSON:**
```swift
struct CreateUserRequest: HPostRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/users"
    var bodyParameters: [String: Any]? {
        [
            "name": "John Doe",
            "email": "john@example.com",
            "age": 30
        ]
    }
}
```

**Example - POST with Encodable Model:**
```swift
struct CreateUserRequest: HPostRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/users"
    
    let user: UserInput
    
    var bodyParameters: [String: Any]? {
        user.asDictionary()
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
    
    var bodyParameters: [String: Any]? {
        [
            "image": imageData,
            "description": description
        ]
    }
    var bodyType: HRequestDataType { .multipart }
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
    var bodyParameters: [String: Any]? { get }
    var bodyType: HRequestDataType { get }
}
```

**Example - Update User:**
```swift
struct UpdateUserRequest: HPutRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/users/1"
    var bodyParameters: [String: Any]? {
        [
            "name": "Jane Doe",
            "email": "jane@example.com",
            "age": 28
        ]
    }
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
    var bodyParameters: [String: Any]? { get }
    var bodyType: HRequestDataType { get }
}
```

**Example - Partial Update:**
```swift
struct UpdateUserEmailRequest: HPatchRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/users/1"
    var bodyParameters: [String: Any]? {
        [
            "email": "newemail@example.com"
        ]
    }
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
    var headerParameters: [String: String]? { get { ["X-API-Version": "2.0"] } set { } }
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
    var retries: Int? { get { 3 } set { } }  // Will retry up to 3 times on failure
}
```

### Custom Timeout

Timeout is configured through the URLSession configuration, not per-request:

```swift
// Configure custom URLSession with timeout
let configuration = URLSessionConfiguration.default
configuration.timeoutIntervalForRequest = 180  // 3 minutes
configuration.timeoutIntervalForResource = 300  // 5 minutes

let customSession = URLSession(configuration: configuration)
await Harbor.setCustomURLSession(customSession)
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
    case api(statusCode: Int, data: Data)
    case invalidHttpResponse
    case invalidRequest
    case authProviderNeeded
    case authNeeded
    case codable(modelName: String, error: Error)
    case noConnection
    case malformedRequest
    case timeout
    case cannotFindHost
    case cancelled
    case certificate
    case noCachedDataFound
}
```

**Using mapURLError:**
```swift
// Convert URLError to HRequestError
func handleURLError(_ error: URLError) -> HRequestError {
    return HRequestError.mapURLError(error)
}

// Example: URLError.cancelled -> HRequestError.cancelled
// Example: URLError.timedOut -> HRequestError.timeout
// Example: URLError.notConnectedToInternet -> HRequestError.noConnection
// Example: URLError.cannotFindHost -> HRequestError.cannotFindHost
// Example: URLError.serverCertificateUntrusted -> HRequestError.certificate
```

**Detailed Error Handling:**
```swift
let response = await request.request()
switch response {
case .success(let data):
    // Handle success
case .error(let error):
    switch error {
    case .api(let statusCode, _):
        // Handle API errors with specific status codes
        if statusCode == 404 {
            // Not found
        }
    case .authNeeded:
        // Re-authenticate user
    case .authProviderNeeded:
        // Set authentication provider
    case .noConnection:
        // Show offline message
    case .cannotFindHost:
        // Show connection error
    case .certificate:
        // SSL/TLS validation failed
    case .timeout:
        // Retry or show timeout message
    case .cancelled:
        // Request was cancelled
    case .codable(let modelName, let error):
        // Log encoding/decoding issue
        print("Failed to encode/decode \(modelName): \(error)")
    case .malformedRequest:
        // Invalid request URL or parameters
    case .noCachedDataFound:
        // No cached data for cache-only request
    case .invalidHttpResponse, .invalidRequest:
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
        var bodyParameters: [String: Any]?
    }
    
    struct Update: HPutRequestProtocol {
        typealias Model = User
        let userId: String
        var url: String { "https://api.example.com/users/\(userId)" }
        var bodyParameters: [String: Any]?
    }
    
    struct Delete: HDeleteRequestProtocol, HRequestWithEmptyResponseProtocol {
        let userId: String
        var url: String { "https://api.example.com/users/\(userId)" }
    }
}
```

### 4. Cache Appropriately

```swift
// Cache static data
struct GetCountriesRequest: HGetRequestProtocol {
    typealias Model = [Country]
    let url = "https://api.example.com/countries"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneWeek))
}

// Don't cache dynamic data
struct GetUserBalanceRequest: HGetRequestProtocol {
    typealias Model = Balance
    let url = "https://api.example.com/balance"
    let cacheType: HCache.CacheType? = nil  // Always fetch fresh
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
