# Harbor Architecture and Design Patterns

This document details the architectural patterns and design principles used in Harbor.

## Architectural Patterns

### 1. Protocol-Oriented Programming (POP)

Harbor is built around Swift protocols, enabling flexibility and extensibility without inheritance overhead.

#### Protocol Hierarchy

```
HRequestBaseRequestProtocol
├── HRequestWithResultProtocol<Model>
│   ├── HGetRequestProtocol
│   ├── HPostRequestProtocol
│   ├── HPutRequestProtocol
│   ├── HPatchRequestProtocol
│   └── HDeleteRequestProtocol
└── HRequestWithEmptyResponseProtocol
    ├── HGetRequestProtocol
    ├── HPostRequestProtocol
    ├── HPutRequestProtocol
    ├── HPatchRequestProtocol
    └── HDeleteRequestProtocol
```

**Key Benefits:**
- **Default implementations** via protocol extensions reduce boilerplate
- **Type safety** with associated types ensures compile-time correctness
- **Composability** allows mixing protocol conformances
- **Testability** through protocol-based mocking

#### Protocol Extensions Pattern

Harbor provides default implementations for common functionality:

```swift
// Base protocol defines the contract
protocol HRequestBaseRequestProtocol {
    var url: String { get }
    var headers: [String: String]? { get }
    // ... more properties
}

// Extension provides default implementations
extension HRequestBaseRequestProtocol {
    var headers: [String: String]? { return nil }
    var needsAuth: Bool { return false }
    var cacheType: HCache.CacheType? { return nil }
}
```

This means you only need to implement what differs from the defaults.

### 2. Actor-Based Concurrency

Harbor embraces Swift's modern concurrency model with actors for thread-safe state management.

#### Global Actor for Request Management

**Location**: `Sources/Harbor/Request/HRequestManager.swift`

```swift
@globalActor
actor HRequestManagerActor {
    static let shared = HRequestManagerActor()
}

@HRequestManagerActor
final class HRequestManager {
    static var config = HConfig()
    // All access to config is automatically serialized
}
```

**Benefits:**
- **Data race prevention**: Compiler enforces serial access to shared state
- **Simplified concurrency**: No manual locks or dispatch queues
- **Async/await integration**: Natural asynchronous programming model

#### Sendable Conformance

Harbor marks types as `Sendable` to ensure safe concurrent access:

```swift
// Immutable structs are inherently Sendable
struct HResponse: Sendable {
    let statusCode: Int
    let data: Data?
}

// Mutable classes require @unchecked Sendable with careful design
final class MyRequest: HPostRequestProtocol, @unchecked Sendable {
    // Must ensure thread-safe access patterns
}
```

### 3. Singleton Pattern

Harbor uses singletons for globally shared resources.

#### Request Manager Configuration

```swift
@HRequestManagerActor
final class HRequestManager {
    static var config = HConfig()  // Global configuration
}
```

**Access Pattern:**
```swift
await Harbor.setAuthProvider(provider)
// Internally calls: HRequestManager.config.authProvider = provider
```

#### Cache Manager

```swift
@HRequestManagerActor
final class Manager {
    static let shared = Manager()
    private let memoryCache = NSCache<NSString, CacheEntry>()
    // ... disk cache implementation
}
```

**Why Singletons Here:**
- **Shared state**: Cache and configuration are application-wide
- **Resource efficiency**: Single NSCache instance, one disk cache
- **Coordination**: Centralized management of network resources

### 4. Strategy Pattern

Harbor uses the Strategy pattern for pluggable behaviors.

#### Authentication Strategy

**Location**: `Sources/Harbor/Auth/HAuthProviderProtocol.swift`

```swift
protocol HAuthProviderProtocol: AnyObject, Sendable {
    func getHeaders() async -> [String: String]
    func isTokenExpired() async -> Bool
    func refreshToken() async throws
}

// Consumers can inject any authentication strategy
await Harbor.setAuthProvider(OAuth2Provider())
// or
await Harbor.setAuthProvider(APIKeyProvider())
```

#### Cache Strategy

**Location**: `Sources/Harbor/Cache/HCacheType.swift`

```swift
enum CacheType {
    case urlCache(urlCache: URLCache, requestCachePolicy: NSURLRequest.CachePolicy)
    case custom(Configuration)
    case disabled
}

// Per-request cache strategy
struct GetUserRequest: HGetRequestProtocol {
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneHour))
}
```

#### Request Source Strategy

**Location**: `Sources/Harbor/Request/HRequestProtocol.swift`

```swift
enum HRequestSource {
    case cacheOnly
    case remoteOnly
    case cacheAndRemote
}

// Stream with different data source strategies
for try await (data, source) in request.requestStream(source: .cacheAndRemote) {
    // First emission from cache, second from network
}
```

### 5. Adapter Pattern

Harbor uses adapters to integrate different protocols and APIs.

#### JSON-RPC Adapter

**Location**: `Sources/HarborJRPC/Request/HJRPCRequestWrapper.swift`

JSON-RPC requests are adapted to Harbor's REST protocol system:

```swift
// User defines JSON-RPC request
struct EthBlockNumber: HJRPCRequestProtocol {
    typealias Model = String
    var method: String = "eth_blockNumber"
}

// Internally wrapped as POST request
struct HJRPCRequestWrapper<Request: HJRPCRequestProtocol>: HPostRequestProtocol {
    let originalRequest: Request
    
    var bodyParameters: [String: Any]? {
        ["jsonrpc": "2.0", "method": originalRequest.method]
    }
}
```

This adapter allows JSON-RPC requests to use Harbor's infrastructure transparently.

## Component Architecture

### Core Components Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        Harbor API                           │
│                   (Static methods)                          │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                   HRequestManager                           │
│              (@HRequestManagerActor)                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    HConfig                          │   │
│  │  • authProvider: HAuthProviderProtocol?            │   │
│  │  • defaultHeaders: [String: String]                │   │
│  │  • mtls: HmTLS?                                    │   │
│  │  • sslPinningKeys: [String]                        │   │
│  │  • cacheType: HCache.CacheType        │   │
│  └─────────────────────────────────────────────────────┘   │
└──────┬────────────────┬──────────────────┬──────────────────┘
       │                │                  │
       ▼                ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│   HCache     │  │ HURLSession  │  │   HMocker    │
│   Manager    │  │   Delegate   │  │              │
│              │  │              │  │              │
│ • NSCache    │  │ • SSL Pin    │  │ • Mock       │
│ • FileSystem │  │ • mTLS       │  │   Registry   │
└──────────────┘  └──────────────┘  └──────────────┘
```

### Request Flow

```
User Code
    │
    ├─ Conforms to HGetRequestProtocol/HPostRequestProtocol/etc.
    │
    ▼
Request.request()
    │
    ├─ Check HMocker for registered mock (DEBUG mode)
    │  └─ If found, return mock response immediately
    │
    ├─ Check cache (if cacheType is set)
    │  └─ If valid cache found, return cached response
    │
    ├─ Build URLRequest
    │  ├─ Merge default headers + request headers
    │  ├─ Add auth headers (if needsAuth = true)
    │  ├─ Set HTTP method
    │  └─ Add body parameters
    │
    ├─ Execute URLSession.data(for:delegate:)
    │  └─ Use custom URLSessionDelegate for SSL/mTLS
    │
    ├─ Process response
    │  ├─ Check status code
    │  ├─ Handle 401 (auth refresh + retry)
    │  └─ Decode JSON to Model type
    │
    ├─ Store in cache (if cacheType is set)
    │
    └─ Return HResponse or HResponseWithResult<Model>
```

### Streaming Flow

```
Request.requestStream(source: .cacheAndRemote)
    │
    ├─ Create AsyncThrowingStream<(Model, HOriginType), Error>
    │
    ├─ If source includes .cache
    │  ├─ Check cache
    │  └─ Yield (cachedData, .cache) if found
    │
    ├─ If source includes .remote
    │  ├─ Execute network request
    │  ├─ Yield (remoteData, .remote) when received
    │  └─ Update cache with remote data
    │
    └─ Complete stream
```

## Module Organization

### Harbor (Core Module)

**Purpose**: REST HTTP requests with full feature set

**Submodules:**
- `Auth/`: Authentication provider protocol
- `Cache/`: Two-level cache system
- `Config/`: Global configuration management
- `Debug/`: Debug logging and cURL generation
- `Mock/`: Mock system for testing
- `Request/`: Core request processing, protocols, manager
- `Utils/`: URL builder, PKCS12 parser, SHA256 utilities

### HarborJRPC (Extension Module)

**Purpose**: JSON-RPC 2.0 support built on Harbor

**Components:**
- `Config/`: JSON-RPC specific configuration
- `Request/`: JSON-RPC protocol and wrapper adapter

**Separation Rationale:**
- Optional for users who don't need JSON-RPC
- Cleaner dependency graph
- Separate versioning if needed

## Thread Safety Model

### Actor Isolation

All shared mutable state is protected by actors:

```swift
// Configuration access is serialized
await Harbor.setAuthProvider(provider)  // Suspends until safe to modify

// Cache access is serialized
await cache.store(data, for: key)       // Suspends until safe to write

// No data races possible
```

### Sendable Requirements

```swift
// Models must be Sendable to cross actor boundaries
struct User: Codable, Sendable {
    let id: Int
    let name: String
}

// Requests can be structs (implicitly Sendable)
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    // ...
}
```

### Concurrency Guarantees

1. **Configuration changes** are atomic and visible to all subsequent requests
2. **Cache operations** are serialized and consistent
3. **Concurrent requests** are safe and don't interfere with each other
4. **Mock registration** is thread-safe for test isolation

## Design Principles

### 1. Progressive Disclosure

Simple cases are simple, complexity is opt-in:

```swift
// Minimal implementation
struct SimpleRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/user"
}

// Full-featured implementation
struct AdvancedRequest: HPostRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/user"
    var bodyParameters: [String: Any]? {
        ["name": "John"]
    }
    let headers = ["X-Custom": "Value"]
    let needsAuth = true
    let retries = 3
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneHour))
}
```

### 2. Composition Over Inheritance

Protocols and extensions enable behavior composition:

```swift
// Mix protocols for additional capabilities
struct MyRequest: HGetRequestProtocol, HDebugRequestProtocol {
    // Gets request execution from HGetRequestProtocol
    // Gets debug logging from HDebugRequestProtocol
}
```

### 3. Type Safety

Generic associated types prevent runtime type errors:

```swift
protocol HRequestWithResultProtocol {
    associatedtype Model: Decodable, Sendable
    // Compiler ensures response type matches Model
}
```

### 4. Fail-Safe Defaults

Sensible defaults minimize configuration:

```swift
// These all have defaults:
var headers: [String: String]? { nil }
var needsAuth: Bool { false }
var retries: Int { 0 }
var timeout: TimeInterval { 60 }
```

### 5. Explicit Over Implicit

Important behaviors require explicit opt-in:

```swift
// Must explicitly enable auth
let needsAuth: Bool = true

// Must explicitly configure cache
let cacheType = HCache.CacheType.custom(HCache.Configuration(expirationTime: .oneHour))
```

## Performance Considerations

### Cache Performance

- **Memory cache (L1)**: ~2.5-2.9x faster than network requests
- **Disk cache (L2)**: Faster than network for large payloads
- **Cache key**: SHA256 of URL + parameters for uniqueness

### Concurrency Performance

- **Actor isolation**: Minimal overhead for configuration access
- **Parallel requests**: Full concurrency, no artificial serialization
- **Async/await**: Efficient suspend/resume without thread blocking

### Memory Management

- **NSCache**: Automatic eviction under memory pressure
- **Disk cache**: Configurable size limits per object
- **Request lifecycle**: Short-lived, minimal retained state

## Related Files

**Architecture Implementation:**
- `Sources/Harbor/Request/HRequestProtocol.swift` - Protocol definitions
- `Sources/Harbor/Request/HRequestManager.swift` - Core processing logic
- `Sources/Harbor/Config/HConfig.swift` - Configuration management
- `Sources/HarborJRPC/Request/HJRPCRequestWrapper.swift` - Adapter example

**Pattern Examples:**
- `Example/HarborExample/Requests/` - Various request implementations
- `Tests/HarborTests/` - Pattern usage in tests
