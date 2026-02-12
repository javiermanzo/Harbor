# Harbor Basic Examples

Practical examples for common Harbor usage patterns.

## Simple GET Request

### Minimal GET Request

```swift
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/users/1"
}

// Execute
let response = await GetUserRequest().request()
switch response {
case .success(let user):
    print("User: \(user.name)")
case .error(let error):
    print("Error: \(error)")
}
```

### GET with Path Parameters

```swift
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let userId: String
    var url: String { "https://api.example.com/users/\(userId)" }
}

// Usage
let response = await GetUserRequest(userId: "123").request()
```

### GET with Query Parameters

```swift
struct SearchUsersRequest: HGetRequestProtocol {
    typealias Model = SearchResults
    let url: String = "https://api.example.com/users/search"
    
    let searchTerm: String
    let page: Int
    let limit: Int
    
    var queryParameters: [String: Any]? {
        return [
            "q": searchTerm,
            "page": page,
            "limit": limit
        ]
    }
}

// Usage - Executes: GET /users/search?q=john&page=1&limit=20
let response = await SearchUsersRequest(
    searchTerm: "john",
    page: 1,
    limit: 20
).request()
```

### GET with Caching

```swift
struct GetUserProfileRequest: HGetRequestProtocol {
    typealias Model = UserProfile
    let userId: String
    var url: String { "https://api.example.com/users/\(userId)/profile" }
    let cacheConfiguration: HCache.Configuration? = .enabled(expirationTime: .oneHour)
}

// First call - fetches from network and caches
let response1 = await GetUserProfileRequest(userId: "123").request()

// Second call within one hour - returns cached data
let response2 = await GetUserProfileRequest(userId: "123").request()
```

## POST Requests

### Simple POST with JSON

```swift
struct CreateUserRequest: HPostRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/users"
    
    let name: String
    let email: String
    
    var bodyParameters: HBodyParameters? {
        return .json([
            "name": name,
            "email": email
        ])
    }
}

// Usage
let response = await CreateUserRequest(
    name: "John Doe",
    email: "john@example.com"
).request()
```

### POST with Codable Model

```swift
struct UserInput: Encodable {
    let name: String
    let email: String
    let age: Int
    let address: Address
}

struct CreateUserRequest: HPostRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/users"
    
    let userInput: UserInput
    
    var bodyParameters: HBodyParameters? {
        guard let data = try? JSONEncoder().encode(userInput),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return .json(dict)
    }
}

// Usage
let input = UserInput(
    name: "Jane Doe",
    email: "jane@example.com",
    age: 28,
    address: Address(street: "123 Main St", city: "Boston")
)

let response = await CreateUserRequest(userInput: input).request()
```

### POST without Response Body

```swift
struct LogEventRequest: HPostRequestProtocol, HRequestWithEmptyResponseProtocol {
    let url: String = "https://api.example.com/events"
    
    let eventType: String
    let timestamp: Date
    
    var bodyParameters: HBodyParameters? {
        return .json([
            "event_type": eventType,
            "timestamp": timestamp.timeIntervalSince1970
        ])
    }
}

// Usage
let response = await LogEventRequest(
    eventType: "user_login",
    timestamp: Date()
).request()

switch response {
case .success:
    print("Event logged")
case .error(let error):
    print("Failed to log: \(error)")
}
```

## PUT and PATCH Requests

### PUT (Full Update)

```swift
struct UpdateUserRequest: HPutRequestProtocol {
    typealias Model = User
    let userId: String
    var url: String { "https://api.example.com/users/\(userId)" }
    
    let name: String
    let email: String
    let age: Int
    
    var bodyParameters: HBodyParameters? {
        return .json([
            "name": name,
            "email": email,
            "age": age
        ])
    }
}

// Usage - Updates all user fields
let response = await UpdateUserRequest(
    userId: "123",
    name: "Jane Doe",
    email: "jane@example.com",
    age: 28
).request()
```

### PATCH (Partial Update)

```swift
struct UpdateUserEmailRequest: HPatchRequestProtocol {
    typealias Model = User
    let userId: String
    var url: String { "https://api.example.com/users/\(userId)" }
    
    let newEmail: String
    
    var bodyParameters: HBodyParameters? {
        return .json(["email": newEmail])
    }
}

// Usage - Updates only the email field
let response = await UpdateUserEmailRequest(
    userId: "123",
    newEmail: "newemail@example.com"
).request()
```

## DELETE Requests

### DELETE without Response

```swift
struct DeleteUserRequest: HDeleteRequestProtocol, HRequestWithEmptyResponseProtocol {
    let userId: String
    var url: String { "https://api.example.com/users/\(userId)" }
}

// Usage
let response = await DeleteUserRequest(userId: "123").request()
switch response {
case .success:
    print("User deleted successfully")
case .error(let error):
    print("Failed to delete user: \(error)")
}
```

### DELETE with Confirmation Response

```swift
struct DeleteResponse: Codable, Sendable {
    let success: Bool
    let message: String
    let deletedId: String
}

struct DeleteUserRequest: HDeleteRequestProtocol {
    typealias Model = DeleteResponse
    let userId: String
    var url: String { "https://api.example.com/users/\(userId)" }
}

// Usage
let response = await DeleteUserRequest(userId: "123").request()
switch response {
case .success(let result):
    print("Deleted: \(result.message)")
case .error(let error):
    print("Failed: \(error)")
}
```

## Response Handling

### Basic Response Handling

```swift
let response = await request.request()

switch response {
case .success(let user):
    // Handle success
    print("User: \(user.name)")
    
case .error(let error):
    // Handle error
    print("Error: \(error)")
}
```

### Detailed Error Handling

```swift
let response = await request.request()

switch response {
case .success(let user):
    updateUI(with: user)
    
case .error(let error):
    switch error {
    case .authNeeded:
        // Redirect to login
        showLoginScreen()
        
    case .noConnectionError:
        // Show offline message
        showOfflineAlert()
        
    case .serverError(let statusCode, let data):
        if statusCode == 404 {
            showNotFoundAlert()
        } else if statusCode >= 500 {
            showServerErrorAlert()
        }
        
    case .decodingError(let decodingError):
        // Log decoding issue
        logError("Failed to decode: \(decodingError)")
        
    case .timeout:
        showTimeoutAlert()
        
    case .cancelled:
        // Request was cancelled
        print("Request cancelled")
        
    default:
        showGenericError(error)
    }
}
```

### SwiftUI Integration

```swift
struct UserView: View {
    @State private var user: User?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if let user = user {
                UserDetailView(user: user)
            } else if let error = errorMessage {
                ErrorView(message: error)
            }
        }
        .task {
            await loadUser()
        }
    }
    
    func loadUser() async {
        isLoading = true
        defer { isLoading = false }
        
        let response = await GetUserRequest(userId: "123").request()
        
        await MainActor.run {
            switch response {
            case .success(let loadedUser):
                self.user = loadedUser
                self.errorMessage = nil
            case .error(let error):
                self.user = nil
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
```

## Custom Headers

### Static Headers

```swift
struct GetDataRequest: HGetRequestProtocol {
    typealias Model = Data
    let url: String = "https://api.example.com/data"
    let headers: [String: String]? = [
        "X-API-Version": "2.0",
        "X-Client-Platform": "iOS"
    ]
}
```

### Dynamic Headers

```swift
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let userId: String
    var url: String { "https://api.example.com/users/\(userId)" }
    
    let sessionId: String
    
    var headers: [String: String]? {
        return [
            "X-Session-ID": sessionId,
            "X-Request-Time": ISO8601DateFormatter().string(from: Date())
        ]
    }
}
```

### Global Default Headers

```swift
// Set once at app launch
await Harbor.setDefaultHeaderParameters([
    "X-API-Key": "your-api-key",
    "X-Client-Version": "1.2.3",
    "Accept-Language": Locale.current.languageCode ?? "en"
])

// All requests will include these headers
struct AnyRequest: HGetRequestProtocol {
    // Automatically includes default headers
}
```

## Configuration

### Set Global Cache

```swift
// In AppDelegate or app initialization
await Harbor.setDefaultCacheConfiguration(.enabled(expirationTime: .oneHour))

// All requests without explicit cache config will use this
```

### Set Custom URLSession

```swift
let configuration = URLSessionConfiguration.default
configuration.timeoutIntervalForRequest = 30
configuration.timeoutIntervalForResource = 300
configuration.waitsForConnectivity = true

let customSession = URLSession(configuration: configuration)
await Harbor.setCustomURLSession(customSession)
```

### Enable Debug Logging

```swift
// Enable logging
await Harbor.setLoggingEnabled(true)

// Requests with HDebugRequestProtocol will log cURL commands
struct DebugRequest: HGetRequestProtocol, HDebugRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/user"
    var debugType: HDebugRequestType = .requestAndResponse
}

// Output:
// curl -X GET "https://api.example.com/user" -H "Content-Type: application/json"
```

## Organized Request Groups

### Namespace Pattern

```swift
enum UserAPI {
    struct Get: HGetRequestProtocol {
        typealias Model = User
        let userId: String
        var url: String { "https://api.example.com/users/\(userId)" }
    }
    
    struct List: HGetRequestProtocol {
        typealias Model = [User]
        let url = "https://api.example.com/users"
        let page: Int
        var queryParameters: [String: Any]? {
            return ["page": page]
        }
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
let users = await UserAPI.List(page: 1).request()
await UserAPI.Delete(userId: "123").request()
```

### Base Request Pattern

```swift
protocol APIRequest: HGetRequestProtocol {
    var endpoint: String { get }
}

extension APIRequest {
    var url: String { "https://api.example.com/\(endpoint)" }
    var needsAuth: Bool { true }
    var headers: [String: String]? {
        return ["X-API-Version": "2.0"]
    }
}

// Usage
struct GetProfileRequest: APIRequest {
    typealias Model = Profile
    let endpoint = "profile"
}

struct GetSettingsRequest: APIRequest {
    typealias Model = Settings
    let endpoint = "settings"
}
```

## Common Patterns

### Conditional Request Configuration

```swift
struct GetDataRequest: HGetRequestProtocol {
    typealias Model = Data
    let url: String = "https://api.example.com/data"
    let useCache: Bool
    
    var cacheConfiguration: HCache.Configuration? {
        return useCache ? .enabled(expirationTime: .oneHour) : .disabled
    }
}

// Usage
let cached = await GetDataRequest(useCache: true).request()
let fresh = await GetDataRequest(useCache: false).request()
```

### Retry Configuration

```swift
struct ReliableRequest: HGetRequestProtocol {
    typealias Model = Data
    let url: String = "https://api.example.com/data"
    let retries: Int = 3  // Will retry up to 3 times on failure
    let timeout: TimeInterval = 60  // 60 seconds timeout
}
```

### Request with Timeout

```swift
struct QuickRequest: HGetRequestProtocol {
    typealias Model = Data
    let url: String = "https://api.example.com/data"
    let timeout: TimeInterval = 10  // 10 seconds timeout
}
```

## Error Recovery

### Retry Pattern

```swift
func fetchUserWithRetry(userId: String, maxAttempts: Int = 3) async -> User? {
    for attempt in 1...maxAttempts {
        let response = await GetUserRequest(userId: userId).request()
        
        switch response {
        case .success(let user):
            return user
            
        case .error(let error):
            if attempt == maxAttempts {
                print("Failed after \(maxAttempts) attempts")
                return nil
            }
            
            if case .noConnectionError = error {
                // Wait before retry
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
            } else {
                // Don't retry non-network errors
                return nil
            }
        }
    }
    return nil
}
```

### Fallback Pattern

```swift
func getUser(userId: String) async -> User? {
    // Try primary API
    let response1 = await GetUserRequest(userId: userId).request()
    if case .success(let user) = response1 {
        return user
    }
    
    // Fallback to backup API
    let response2 = await GetUserBackupRequest(userId: userId).request()
    if case .success(let user) = response2 {
        return user
    }
    
    // Return nil if both fail
    return nil
}
```

## Related Files

**Example Implementations:**
- `Example/HarborExample/Requests/RESTRequest.swift` - GET request example
- `Example/HarborExample/RequestsView.swift` - SwiftUI usage

**More Examples:**
- [advanced.md](advanced.md) - Advanced patterns
- [jrpc.md](jrpc.md) - JSON-RPC examples
