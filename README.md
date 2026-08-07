<p align="center" width="100%">
    <img width="40%" src="https://raw.githubusercontent.com/javiermanzo/Harbor/main/Resources/Harbor.png"> 
</p>

![Release](https://img.shields.io/github/v/release/javiermanzo/Harbor?style=flat-square)
![CI](https://img.shields.io/github/actions/workflow/status/javiermanzo/Harbor/unit-tests.yml?style=flat-square)
[![Swift](https://img.shields.io/badge/Swift-5.9_6.0-orange?style=flat-square)](https://img.shields.io/badge/Swift-5.9_6.0-orange?style=flat-square)
[![Platforms](https://img.shields.io/badge/Platforms-macOS_iOS-yellowgreen?style=flat-square)](https://img.shields.io/badge/Platforms-macOS_iOS-yellowgreen?style=flat-square) 
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](https://swiftpackageindex.com/javiermanzo/Harbor)

Harbor is a modern, protocol-oriented networking library for Swift built to be resilient, flexible, and completely Swift 6 Strict Concurrency ready. It provides powerful features like Multi-layer Caching, mTLS, SSL Pinning, JSON-RPC, and Streaming out of the box.

## Table of Contents
- [Requirements](#requirements)
- [Installation](#installation)
- [Basic Usage](#basic-usage)
  - [Request Protocols](#request-protocols)
  - [Making Requests](#making-requests)
  - [Handling Responses](#handling-responses)
  - [Canceling Requests](#canceling-requests)
- [Advanced Usage](#advanced-usage)
  - [Configuration](#configuration)
  - [Authentication](#authentication)
  - [Retry Policies](#retry-policies)
  - [Security (mTLS & SSL Pinning)](#security-mtls--ssl-pinning)
  - [Advanced Caching](#advanced-caching)
  - [Multipart Requests](#multipart-requests)
  - [Streaming Requests](#streaming-requests)
  - [JSON-RPC](#json-rpc)
  - [Debugging & Logging](#debugging--logging)
  - [Mocking](#mocking)
- [AI Assistant Skills](#ai-assistant-skills)
- [Contributing](#contributing)
- [License](#license)

---

## Requirements
- Swift 5.9+
- iOS 15.0+ / macOS 12.0+

## Installation

### Swift Package Manager
Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/javiermanzo/Harbor.git", from: "4.0.0")
]
```

Then add the products you need to your target:

```swift
.target(
    dependencies: [
        .product(name: "Harbor", package: "Harbor"),
        .product(name: "HarborJRPC", package: "Harbor") // Only if you need JSON-RPC support
    ]
)
```

---

## Basic Usage

Harbor's philosophy is protocol-oriented. You declare your requests as structs that conform to specific HTTP method protocols. This keeps your networking code immutable, type-safe, and cleanly separated.

### Request Protocols

Harbor provides base protocols for each HTTP method:
- `HGetRequestProtocol`
- `HPostRequestProtocol`
- `HPutRequestProtocol`
- `HPatchRequestProtocol`
- `HDeleteRequestProtocol`

### Making Requests

To make a GET request, create a `struct` that conforms to `HGetRequestProtocol`. You just need to provide the `url` and the `Model` it should decode to.

```swift
import Harbor

struct User: Decodable {
    let id: Int
    let name: String
}

struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/users/1"
}

Task {
    do {
        // The request() method directly returns your decoded Model
        let user = try await GetUserRequest().request()
        print(user.name)
    } catch {
        print("Error: \(error)")
    }
}
```

For a POST request, conform to `HPostRequestProtocol` and provide `bodyParameters`.

```swift
struct CreateUserRequest: HPostRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/users"
    
    var bodyParameters: [String: Any]? {
        ["name": "Jane", "role": "admin"]
    }
}
```

### Handling Responses

If you need full access to the underlying HTTP response (like headers, status code, or the raw data), you can use `requestResult()` instead of `request()`:

```swift
let responseResult = await GetUserRequest().requestResult()

switch responseResult {
case .success(let response):
    print("Code: \(response.statusCode)")
    print("Headers: \(response.headers ?? [:])")
    print("Model: \(response.model)")
case .error(let error):
    print("Failed with error: \(error)")
}
```

### Canceling Requests

When calling `request()`, an `id` parameter is generated implicitly if not provided. You can provide a custom `id` to manually track and cancel requests.

```swift
let requestId = "my-unique-request-id"
Task {
    do {
        let user = try await GetUserRequest(id: requestId).request()
    } catch {
        // Will catch cancellation error if canceled
    }
}

// Somewhere else in your code:
await HRequestManagerActor.shared.cancelRequest(id: requestId)
```

---

## Advanced Usage

Harbor provides a robust set of tools for enterprise-level applications, all built on top of Swift's concurrency model.

### Configuration

You can configure Harbor globally via the `Harbor` actor. This applies to all requests unless overridden locally.

```swift
// Set default headers to be sent with every request
await Harbor.setDefaultHeaderParameters(["X-Client-Version": "1.0.0"])

// Set a custom URLSession
let session = URLSession(configuration: .ephemeral)
await Harbor.setCustomURLSession(session)
// To restore the default session, pass nil:
// await Harbor.setCustomURLSession(nil)

// Set global timeout (default is 15 seconds)
await Harbor.setDefaultTimeoutInterval(30)
```

### Authentication

Harbor handles authentication injection and 401 refresh flows transparently through `HAuthProviderProtocol`.

```swift
class MyAuthProvider: HAuthProviderProtocol {
    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        // Return your header, or nil if unauthenticated
        return HAuthorizationHeader(key: "Authorization", value: "Bearer my-token")
    }
    
    func authFailed() async {
        // Called automatically when a request receives a 401 Unauthorized status.
        // Refresh your token here. Harbor will automatically retry the original request
        // once if the authorization header changes.
    }
}

// Register it globally
await Harbor.setAuthProvider(MyAuthProvider())
```

To enable auth for a specific request, simply set `needsAuth` to `true` (by default it is `false`):
```swift
struct SecureRequest: HGetRequestProtocol {
    typealias Model = SecretData
    let url = "https://api.example.com/secret"
    let needsAuth = true
}
```

### Retry Policies

You can easily make your requests resilient to transient network failures by setting the `retries` property.

```swift
struct ResilientRequest: HGetRequestProtocol {
    typealias Model = Data
    let url = "https://api.example.com/flaky-endpoint"
    let retries: Int? = 3 // Will retry up to 3 times automatically (default is 0)
}
```

### Security (mTLS & SSL Pinning)

Harbor provides first-class support for mutual TLS and SSL pinning to ensure maximum security.

#### SSL Pinning
Pins use the standard `base64(SHA256(SPKI))` format. You can generate them from a certificate using `Harbor.computePin(for:)` or via OpenSSL.

```swift
let pins = ["YLh1dUR9y6Kja30RrAn7JKnbQG/uEtLMkBgFF2Fuihg="]
// Apply globally
await Harbor.setSSLPinningKeys(pins)

// Or scope to specific hosts
await Harbor.setSSLPinningKeys(pins, forHosts: ["api.example.com"])
```

#### mTLS
Extracts your client identity from a PKCS#12 archive safely off the main thread. The password closure is called on-demand to prevent retaining sensitive strings in memory.

```swift
let mTLS = HMTLS(p12FileUrl: myCertURL) { "myPassword" }
try await Harbor.setMTLS(mTLS)
```

### Advanced Caching

Harbor features a multi-layer cache (Memory + Disk) that fully respects HTTP `Cache-Control`, `ETag`, and `Vary` directives. By default, Harbor uses `.urlCache` (which relies on `URLCache.shared`). 

To enable the advanced custom multi-layer cache:

```swift
// Configure the custom cache limits
let config = HCache.Configuration(
    expirationTime: .oneHour,
    maxObjectSizeInMBs: 10,
    memoryCacheCapacityInMBs: 100,
    diskCacheCapacityInMBs: 500
)

// Set globally
await Harbor.setDefaultCacheType(.custom(config))
```

You can also override the cache policy per request:
```swift
struct CachedRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/user"
    var cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneDay))
}
```

You can easily retrieve cached data or clear the cache:
```swift
// Retrieve cached ETags
let eTag = await GetUserRequest().cachedETag()

// Fetch only from cache without hitting the network
let cachedUser = await GetUserRequest().cache()

// Clear cache for a specific request
await GetUserRequest().clearCache()

// Clear all cache
await Harbor.clearAllCache()
```

### Multipart Requests

Set `bodyType` to `.multipart` and use `HFormValue` for your parameters to upload files alongside text data.

```swift
struct UploadRequest: HPostRequestProtocol {
    typealias Model = SuccessModel
    let url = "https://api.example.com/upload"
    let bodyType: HRequestBodyType = .multipart
    
    var bodyParameters: [String: Any]? {
        [
            "username": "Javier",
            "avatar": HFormValue(data: imageData, fileName: "avatar.png", mimeType: "image/png")
        ]
    }
}
```

If you just need to send raw `Data`, you can use the `rawBody` property instead of `bodyParameters`.

### Streaming Requests

Use `requestStream()` to read large responses chunk by chunk using Swift's `AsyncThrowingStream`.

```swift
let stream = GetLargeFileRequest().requestStream()

for try await chunk in stream {
    print("Received chunk of \(chunk.count) bytes")
}
```
You can optionally define a `source` to read from cache and/or remote: `.cacheOnly`, `.remoteOnly`, `.cacheAndRemote`.

### JSON-RPC

Harbor natively supports Ethereum-style JSON-RPC 2.0 requests via the `HarborJRPC` target. It fully implements the 2.0 spec, including batching and notifications.

```swift
import HarborJRPC

// Setup global JRPC Config
try await HarborJRPC.configure(url: "https://rpc.example.com", jrpcVersion: "2.0")

struct BlockNumberRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method = "eth_blockNumber"
    // parameters can be omitted, or provided via .positioned([Any]) or .named([String: Any])
}

let blockNumber = try await BlockNumberRequest().request()
```

### Debugging & Logging

Harbor integrates the `LogBird` framework under the hood for clean, structured console output. 

```swift
// Enable logging (enabled by default in DEBUG, disabled in RELEASE)
await Harbor.setLoggingEnabled(true)

// Configure sensitive header redaction to prevent token leaks in the console
await Harbor.setLogSensitiveHeaders(["Authorization", "Cookie", "X-API-Key"])
```

Requests automatically print a valid `cURL` command in the console to easily replay them in your terminal. All sensitive headers are redacted by default.

### Mocking

Mocking in Harbor operates at the `URLProtocol` layer, meaning your production code requires **zero changes** to support mocks.

```swift
// 1. Enable mocks globally
await Harbor.setMocksEnabled(true)

// 2. Register a mock for a request
let mock = HMock(
    request: GetUserRequest.self,
    result: .success(User(id: 1, name: "Mocked User")),
    delay: 1.5 // Simulate a 1.5 second network delay
)
await Harbor.register(mock: mock)

// 3. Fire the request in your app. It will be intercepted and return the mock!
```

---

## AI Assistant Skills

If you use an AI coding assistant (like GitHub Copilot, Cursor, Gemini, or Claude), Harbor provides deep built-in documentation so the AI can learn exactly how to use the framework.

Point your AI Assistant to the following files in this repository:

- [**AGENTS.md**](AGENTS.md): The root AI instruction file. Gives the AI immediate context on what Harbor is, how its protocols work, and its architectural rules.
- [**.agents/skills/harbor/SKILL.md**](.agents/skills/harbor/SKILL.md): The detailed framework AI skill. Contains advanced context and links to deep-dive files for caching, security, architecture, and testing.
- [**.agents/skills/harbor-migration-v3-to-v4/SKILL.md**](.agents/skills/harbor-migration-v3-to-v4/SKILL.md): The AI migration guide. Instruct your AI to read this if you are upgrading a codebase from Harbor v3 to Harbor v4. It contains a list of all breaking changes and how to refactor them automatically.

---

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to get started.

## License

Harbor is available under the MIT license. See the [LICENSE.md](LICENSE.md) file for more info.
