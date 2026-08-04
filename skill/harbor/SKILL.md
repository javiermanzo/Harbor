---
name: harbor
description: Complete guide for working with Harbor, a protocol-oriented Swift networking framework. Use this skill whenever you need to implement HTTP requests, configure caching (URLCache, ETags, custom cache), set up security (mTLS, SSL Pinning), write tests with mocks, work with Harbor's architecture, or handle JSON-RPC requests. Essential for any Swift/iOS/macOS networking implementation.
user-invocable: true
---

# Harbor Networking Framework

Harbor is a protocol-oriented networking library for Swift that provides a modern, async/await-based approach to HTTP requests with comprehensive features for production applications.

## Quick Overview

Harbor supports:
- REST and JSON-RPC 2.0 requests
- **Dual caching system**: URLCache (automatic ETags) + Custom cache (manual control)
- Authentication with custom providers
- Security features (mTLS, SSL Pinning)
- Mock system for testing
- Debug mode with cURL output
- Streaming with AsyncThrowingStream
- Swift Concurrency (async/await, actors)
- Swift 6 compatible

## Core Components

### Request Management
- **Location**: `Sources/Harbor/Request/HRequestManager.swift`
- **Purpose**: Processes HTTP requests, handles authentication, retries, and errors
- **Actor**: `@HRequestManagerActor` for thread-safe operations

### Configuration
- **Location**: `Sources/Harbor/Config/HConfig.swift`
- **API**: `Harbor` enum with static methods for global configuration
- **Thread-safe**: Actor-isolated configuration

### Cache System
- **Location**: `Sources/Harbor/Cache/`
- **URLCache** (default): Automatic ETags, 304 responses, zero configuration
- **Custom Cache**: Two-level (memory + disk), manual TTL, size limits
- **Policy-based**: Choose per request via `cacheType`

### Security
- **mTLS**: `Sources/Harbor/Request/HmTLS.swift`
- **SSL Pinning**: `Sources/Harbor/Request/HURLSessionDelegate.swift`
- **Auth Provider**: Custom authentication via `HAuthProviderProtocol`

## Code Conventions

### Naming Conventions
- **Prefix "H"** on all public types: `HRequest`, `HResponse`, `HCache`
- **Protocol suffix**: `HRequestProtocol`, `HAuthProviderProtocol`
- **Manager suffix**: `HRequestManager`, `HCache.Manager`
- **Descriptive names**: `HRequestWithResultProtocol`, `HCacheConfiguration`

### File Organization
```
Sources/Harbor/
├── Auth/          # Authentication providers
├── Cache/         # Cache system (URLCache + Custom)
├── Config/        # Global configuration
├── Debug/         # Debug and logging
├── Mock/          # Testing mocks
├── Request/       # Core request handling
└── Utils/         # Utilities (URL builder, PKCS12, SHA256)
```

### Swift Best Practices
- Use `async/await` for all asynchronous operations
- Mark types as `Sendable` for thread safety
- Use `@globalActor` for shared state
- Prefer `struct` for immutable requests
- Use `final class` with `@unchecked Sendable` for mutable requests

## Quick Reference

### Basic GET Request (Default: URLCache with ETags)
```swift
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/user"
    // cacheType = .urlCache by default (automatic ETags)
}

let response = await GetUserRequest().request()
```

### POST Request with JSON
```swift
struct CreateUserRequest: HPostRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/user"
    var bodyParameters: [String: Any]? {
        ["name": "John", "email": "john@example.com"]
    }
}
```

### Global Configuration
```swift
// Set authentication
await Harbor.setAuthProvider(MyAuthProvider())

// Configure default headers
await Harbor.setDefaultHeaderParameters(["X-API-Key": "secret"])

// Enable SSL Pinning
await Harbor.setSSlPinningKeys(["sha256hash1", "sha256hash2"])

// Configure mTLS
let mtls = HmTLS(p12FileUrl: certUrl, password: "password")
await Harbor.setMTLS(mtls)

// Set default cache type
await Harbor.setDefaultCacheType(.custom(HCache.Configuration(expirationTime: .oneDay)))
```

### Cache Policies (NEW)
```swift
// Option 1: URLCache (default) - Automatic ETags, 304 responses
struct GetUsersRequest: HGetRequestProtocol {
    typealias Model = [User]
    let url = "https://api.example.com/users"
    // cacheType = .urlCache by default
}

// Option 2: Custom cache - Manual TTL and size control
struct GetUsersRequest: HGetRequestProtocol {
    typealias Model = [User]
    let url = "https://api.example.com/users"
    var cacheType: HCache.CacheType? = .custom(HCache.Configuration(
        expirationTime: .oneHour,
        maxObjectSizeInMBs: 10,
        memoryCacheCapacityInMBs: 100
    ))
}

// Option 3: Custom URLCache with specific limits
struct GetUsersRequest: HGetRequestProtocol {
    typealias Model = [User]
    let url = "https://api.example.com/users"
    var cacheType: HCache.CacheType? = .urlCache(URLCache(
        memoryCapacity: 100 * 1024 * 1024,
        diskCapacity: 500 * 1024 * 1024
    ))
}

// Option 4: No caching
struct GetUsersRequest: HGetRequestProtocol {
    typealias Model = [User]
    let url = "https://api.example.com/users"
    var cacheType: HCache.CacheType? = .disabled
}
```

## Cache System

Harbor provides two caching strategies:

### URLCache (Default)
- Automatic ETags and 304 responses
- Respects Cache-Control headers
- Zero configuration required (50MB memory, 200MB disk)
- Custom URLCache can be passed for specific limits
- Recommended for most use cases

### Custom Cache
- Two-level cache (NSCache L1 + Disk L2)
- Manual TTL control
- Size limits per object
- Use when you need fine-grained control

```swift
// URLCache configuration
let customURLCache = URLCache(
    memoryCapacity: 100 * 1024 * 1024,  // 100MB memory
    diskCapacity: 500 * 1024 * 1024     // 500MB disk
)
let cacheType: HCache.CacheType = .urlCache(customURLCache)

// Custom cache configuration
let config = HCache.Configuration(
    expirationTime: .oneHour,        // Cache TTL
    maxObjectSizeInMBs: 10,           // Max object size (default: 10MB)
    memoryCacheCapacityInMBs: 100     // Memory cache size (default: 100MB)
)
let cacheType: HCache.CacheType = .custom(config)
```

### Response Handling
```swift
let response = await request.request()
switch response {
case .success(let user):
    print("User: \(user)")
case .error(let error):
    switch error {
    case .authNeeded:
        // Handle authentication
    case .noConnection:
        // Handle connection error
    default:
        print("Error: \(error)")
    }
}
```

## Detailed Documentation

For in-depth information, see the specialized documentation files:

### Architecture and Patterns
See [architecture.md](architecture.md) for:
- Protocol-Oriented Programming patterns
- Actor-based concurrency model
- Design patterns (Singleton, Strategy, Adapter)
- Component architecture diagrams

### Protocol Guide
See [protocols.md](protocols.md) for:
- Complete protocol hierarchy
- When to use each protocol type
- Required vs optional properties
- Implementation examples for each HTTP method

### Cache System
See [cache.md](cache.md) for:
- Two-level cache architecture
- Configuration options (global vs per-request)
- Expiration times and size limits
- HTTP header compliance
- Streaming with cache sources

### Security
See [security.md](security.md) for:
- mTLS setup with PKCS12 certificates
- SSL Pinning with SHA256 hashes
- Certificate rotation strategies
- Authentication provider implementation

### Testing
See [testing.md](testing.md) for:
- Mock system usage
- Given-When-Then test structure
- Setup and teardown patterns
- Best practices for test isolation

### Examples
See the `examples/` directory for:
- [basic.md](examples/basic.md): GET, POST, response handling
- [advanced.md](examples/advanced.md): Multipart, retry, streaming, custom URLSession
- [jrpc.md](examples/jrpc.md): JSON-RPC 2.0 requests

## Key Files Reference

**Core Files:**
- `Sources/Harbor/Harbor.swift` - Public API entry point
- `Sources/Harbor/Request/HRequestProtocol.swift` - Base protocol definitions
- `Sources/Harbor/Config/HConfig.swift` - Configuration management

**Example Files:**
- `Example/HarborExample/RequestsView.swift` - SwiftUI usage examples
- `Example/HarborExample/Requests/` - Various request implementations

**Test Files:**
- `Tests/HarborTests/HarborTests.swift` - Integration tests
- `Tests/HarborTests/HarborCacheTests.swift` - Cache tests
- `Tests/HarborTests/Mocks/MocksRequest.swift` - Reusable mock classes

## Common Tasks

### Creating a New Request
1. Choose the appropriate protocol (`HGetRequestProtocol`, `HPostRequestProtocol`, etc.)
2. Define the response `Model` type
3. Specify the `url` property
4. Add optional configurations (cache, auth, headers)
5. Call `request()` to execute

### Configuring Authentication
1. Implement `HAuthProviderProtocol`
2. Return auth headers in `getHeaders()`
3. Handle token refresh in `isTokenExpired()` and `refreshToken()`
4. Set globally: `await Harbor.setAuthProvider(provider)`

### Setting Up Tests
1. Create mock response JSON
2. Create `HMock` with status code and JSON
3. Register: `await Harbor.register(mock: mock)`
4. Execute request and verify response
5. Clean up: `await Harbor.removeAllMocks()`

## Error Handling

Harbor provides comprehensive error handling via `HRequestError`:

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

### Converting URLError to HRequestError

Use `mapURLError` to convert standard URL errors to Harbor errors:

```swift
let error: HRequestError = HRequestError.mapURLError(urlError)
// Handles: cancelled, timeout, noConnection, cannotFindHost, certificate, etc.
```

See [protocols.md](protocols.md) for detailed error handling examples.

## Version Information

- **Current Version**: 3.1.0
- **Minimum iOS**: 15.0
- **Minimum macOS**: 14.0
- **Swift Version**: 5.9+ (Swift 6 compatible)
- **Dependencies**: LogBird 2.1.0

## Additional Resources

- **README**: Project root `README.md` for installation and overview
- **CHANGELOG**: `CHANGELOG.md` for version history
- **Example Project**: `Example/HarborExample.xcodeproj` for live demonstrations
