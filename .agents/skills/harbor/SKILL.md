# Harbor - Context for Agents

This document provides massive system instructions and full context of the Harbor library for AI agents operating on this repository.

## Overview
Harbor is a modern, lightweight, and robust networking library for Swift, built from the ground up to support Swift 6's strict concurrency model. It relies on `async/await` and Actors to provide a thread-safe environment for making REST and JSON-RPC API requests.

## Architecture & Concurrency Rules

1. **Protocols, not Classes**: Harbor requires requests to be defined as `struct`s conforming to protocols like `HGetRequestProtocol`, `HPostRequestProtocol`, etc. This keeps networking code immutable, type-safe, and self-contained. 
2. **Default Implementations**: The protocols already provide defaults for properties like `needsAuth` (false), `retries` (0), `headerParameters` (nil), `cacheType` (nil). Only override what you need.
3. **Async/Await First**: Everything is `async`. You fetch data via `.request()` and Harbor returns the `Decodable` model directly. If it fails, it `throws`. If you need raw headers and status codes, use `.requestResult()`.
4. **Actor Isolation**: Global configuration lives in the `Harbor` enum (which is `@HRequestManagerActor` isolated). Configuration is done using `await Harbor.setSomething(...)`. Since this runs on a global actor, always ensure your UI updates happen on `@MainActor` when fetching configurations.
5. **No Callbacks**: Never use escaping closures or callbacks for requests. Always use `try await`.

## Core Features & Configuration

### 1. Network & Configurations
```swift
// Global configurations
await Harbor.setDefaultTimeoutInterval(30)
await Harbor.setDefaultHeaderParameters(["X-Client-Version": "4.0.0"])

// Custom URLSession (Harbor uses it as-is, isolating request cache states)
await Harbor.setCustomURLSession(URLSession(configuration: .ephemeral))
// To restore the default Harbor session, pass nil:
// await Harbor.setCustomURLSession(nil)
```

### 2. Advanced Caching
Harbor features a multi-layer cache (Memory + Disk). It respects HTTP directives (`Cache-Control`, `ETag`, `Vary`) and supports conditional revalidation (304 Not Modified).
```swift
let config = HCache.Configuration(
    expirationTime: .oneHour, 
    maxObjectSizeInMBs: 10, 
    memoryCacheCapacityInMBs: 100, 
    diskCacheCapacityInMBs: 500
)
await Harbor.setDefaultCacheType(.custom(config))

// You can override it per request
struct MyRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com"
    let cacheType: HCache.CacheType? = .urlCache()
}

// Fetch cache directly without network
let cachedUser = await MyRequest().cache()
await Harbor.clearAllCache() // async!
```

### 3. Security (mTLS, SSL Pinning, Redaction)
```swift
// mTLS uses an async throwing password provider to avoid retaining strings in memory
let mTLS = HMTLS(p12FileUrl: certURL) { "myPassword" }
try await Harbor.setMTLS(mTLS)

// SSL Pinning uses base64(SHA256(SPKI)) hashes.
// Old raw key bytes are no longer valid in v4! Generate with:
// openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64
await Harbor.setSSLPinningKeys(["base64(SHA256(SPKI))_hash"], forHosts: ["api.example.com"])

// Redact sensitive data from Debug logs (cURL generation, etc)
await Harbor.setLogSensitiveHeaders(["Authorization", "Cookie"])
```

### 4. Authentication & Retry
```swift
class MyAuthProvider: HAuthProviderProtocol {
    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        // returning nil means "send without auth header"
        return HAuthorizationHeader(key: "Authorization", value: "Bearer token")
    }
    func authFailed() async { /* refresh flow */ }
}
await Harbor.setAuthProvider(MyAuthProvider())
```

### 5. JSON-RPC (HarborJRPC)
Harbor natively supports Ethereum-style JSON-RPC 2.0 requests.
```swift
try await HarborJRPC.configure(url: "https://rpc.example.com", jrpcVersion: "2.0")

struct BlockRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method = "eth_blockNumber"
    // Parameters use the HJRPCParams enum in v4:
    let parameters: HJRPCParams? = .positioned(["latest"])
}
// request() now throws in v4
let block = try await BlockRequest().request()
```

### 6. Streaming & Multipart
- **Streaming**: Call `.requestStream(source: .cacheAndRemote)` to get an `AsyncThrowingStream` that yields elements and origin (`.cache` or `.remote`) chunk by chunk.
- **Multipart**: Set `bodyType = .multipart` and use `HFormValue(data: fileName: mimeType:)` inside `bodyParameters`. To send raw data, use `rawBody`.

### 7. Mocking & Testing
Mocks operate at the `URLProtocol` level, intercepting actual network traffic.
```swift
await Harbor.setMocksEnabled(true)
let mock = HMock(request: GetUserRequest.self, result: .success(User(id: 1)), delay: 1.5)
await Harbor.register(mock: mock)
```

## Example App
The repository includes an `Example/HarborExample` app showcasing every single feature (GET, POST, Caching, Streaming, JRPC, Auth, Retry, Mocking). When modifying the Example App:
- Ensure UI state uses `@State` and isolates networking calls using `Task { await ... }`.
- Always verify that global configuration states (like `Harbor.mocksEnabled`) are accessed correctly without triggering Main Actor warnings.

## CI & Workflow
- Commits must follow Conventional Commits (e.g., `feat:`, `fix:`, `docs:`, `chore:`).
- When adding features, ensure they comply with Swift 6 Strict Concurrency.
- Always run `swift test` and `xcodebuild test` in the Example App to ensure no regressions. The CI handles Unit Tests via GitHub Actions.

## Internal Deep-Dive Documentation
Harbor contains further internal documentation files mapping out specific systems. If you need deep implementation details on specific areas, you can locate them inside `.agents/skills/harbor/`:
- `architecture.md`: In-depth breakdown of request flow and Actor lifecycle.
- `cache.md`: Deep dive into L1/L2 cache storage mechanisms and ETags.
- `security.md`: How `URLSessionDelegate` handles trust evaluation.
- `testing.md`: How `HMocker` intercepts requests via `URLProtocol`.
- `protocols.md`: Comprehensive list of all Harbor protocols.

If migrating a codebase from Harbor v3 to v4, always consult `.agents/skills/harbor-migration-v3-to-v4/SKILL.md`.
