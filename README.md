<p align="center" width="100%">
    <img width="40%" src="https://raw.githubusercontent.com/javiermanzo/Harbor/main/Resources/Harbor.png"> 
</p>

![Release](https://img.shields.io/github/v/release/javiermanzo/Harbor?style=flat-square)
![CI](https://img.shields.io/github/actions/workflow/status/javiermanzo/Harbor/ci.yml?style=flat-square)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?style=flat-square)](https://img.shields.io/badge/Swift-6.0-orange?style=flat-square)
[![Platforms](https://img.shields.io/badge/Platforms-macOS_iOS-yellowgreen?style=flat-square)](https://img.shields.io/badge/Platforms-macOS_iOS-yellowgreen?style=flat-square) 
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](https://swiftpackageindex.com/javiermanzo/Harbor)

Harbor is a protocol-oriented networking library for Swift, built for Swift 6 strict concurrency. It provides a multi-layer cache, authentication with token refresh, retry policies, mTLS, SSL pinning, log redaction, mocking and JSON-RPC 2.0 out of the box.

## Table of Contents
- [Requirements](#requirements)
- [Installation](#installation)
- [Basic Usage](#basic-usage)
  - [Request Protocols](#request-protocols)
  - [Making Requests](#making-requests)
  - [Requests with a Body](#requests-with-a-body)
  - [Handling Errors](#handling-errors)
  - [Cancelling Requests](#cancelling-requests)
- [Advanced Usage](#advanced-usage)
  - [Configuration](#configuration)
  - [Authentication](#authentication)
  - [Retry Policies](#retry-policies)
  - [Security (mTLS & SSL Pinning)](#security-mtls--ssl-pinning)
  - [Custom URLSession](#custom-urlsession)
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
- Swift 6.0+ (Xcode 16+)
- iOS 15.0+ / macOS 14.0+

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
    name: "MyApp",
    dependencies: [
        .product(name: "Harbor", package: "Harbor"),
        .product(name: "HarborJRPC", package: "Harbor") // Only if you need JSON-RPC support
    ]
)
```

---

## Basic Usage

Harbor is protocol-oriented: you declare each request as a `struct` conforming to the protocol of its HTTP method. Requests are `Sendable` values, so they can be created anywhere and sent from any concurrency context.

### Request Protocols

| Protocol | Method | `request()` returns |
| --- | --- | --- |
| `HGetRequestProtocol` | GET | `HResponseWithResult<Model>` |
| `HPostRequestProtocol` | POST | `HResponse` |
| `HPutRequestProtocol` | PUT | `HResponse` |
| `HPatchRequestProtocol` | PATCH | `HResponse` |
| `HDeleteRequestProtocol` | DELETE | `HResponse` |

Every property except `url` (and `bodyParameters` for body requests) has a default: `needsAuth` (`false`), `retryPolicy` (`nil`), `pathParameters`, `headerParameters`, `queryParameters`, `cacheType`, `timeoutInterval` (all `nil`). All requirements are get-only, so you can implement them as `let` constants or computed properties.

### Making Requests

A GET request declares its `url` and the `Model` it decodes to. `request()` never throws: it returns an `HResponseWithResult<Model>` that is either `.success(model)` or `.error(HRequestError)`.

```swift
import Harbor

struct User: Codable, Sendable {
    let id: Int
    let name: String
}

struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User

    let userId: Int

    let url = "https://api.example.com/users/{id}"
    var pathParameters: [String: String]? { ["id": String(userId)] }
    var queryParameters: [String: String]? { ["include": "profile"] }
}

func loadUser() async {
    switch await GetUserRequest(userId: 1).request() {
    case .success(let user):
        print(user.name)
    case .error(let error):
        print("Error: \(error.localizedDescription)")
    }
}
```

Path parameters replace `{name}` placeholders and are percent-encoded (`/` becomes `%2F`, so a value always stays inside one path segment; `..` segments are rejected). Query values are strictly percent-encoded (`+` is sent as `%2B`) and sorted, so the same request always produces the same URL.

To decode with a custom decoder, override `parseData(data:model:)`; the same method is used for cached bodies.

### Requests with a Body

POST, PUT and PATCH requests provide `bodyParameters` (JSON by default). Their `request()` returns an `HResponse` (`.success` or `.error(HRequestError)`).

```swift
struct CreateUserRequest: HPostRequestProtocol {
    let name: String

    let url = "https://api.example.com/users"
    var bodyParameters: [String: Any]? {
        ["name": name, "role": "admin"]
    }
}

func createUser() async {
    if case .error(let error) = await CreateUserRequest(name: "Jane").request() {
        print("Failed: \(error)")
    }
}
```

`bodyParameters` is a get-only requirement: a computed property keeps the request a plain `Sendable` struct (a stored `[String: Any]` would require `@unchecked Sendable`). A body that `JSONSerialization` cannot encode fails with `HRequestError.malformedRequest(reason:)` instead of being sent empty.

The body is the first non-nil of `rawBody`, `multipartBody` and `bodyParameters`. To send pre-encoded data (for example an `Encodable` model) use `rawBody`, which is sent as-is with `Content-Type: application/json` unless `headerParameters` sets a `Content-Type` (header names match case-insensitively, so `content-type` also replaces it):

```swift
struct UpdateUserRequest: HPutRequestProtocol {
    let user: User

    var url: String { "https://api.example.com/users/\(user.id)" }
    var bodyParameters: [String: Any]? { nil }
    var rawBody: Data? { try? JSONEncoder().encode(user) }
}
```

### Handling Errors

`HRequestError` is `Equatable` and covers HTTP and transport failures:

```swift
func handle(_ error: HRequestError) {
    switch error {
    case .api(let statusCode, let data):
        print("HTTP \(statusCode), \(data.count) bytes")
    case .noConnection, .timeout, .cannotFindHost, .cannotConnectToHost:
        print("Network problem: \(error.localizedDescription)")
    case .certificate:
        print("TLS or SSL pinning validation failed")
    case .authNeeded, .authProviderNeeded:
        print("Authentication required")
    case .codable(let modelName, let underlying):
        print("Could not decode \(modelName): \(underlying)")
    case .malformedRequest(let reason):
        print("Invalid request: \(reason ?? "-")")
    case .cancelled:
        break
    case .networkFailure(let urlError):
        print("URLError \(urlError.code)")
    case .unknown(let underlying):
        print("Unexpected: \(underlying)")
    case .invalidHttpResponse, .noCachedDataFound:
        print(error.localizedDescription)
    }
}
```

### Cancelling Requests

Requests follow structured concurrency: cancel the `Task` that awaits them and the request finishes with `HRequestError.cancelled`.

```swift
let task = Task {
    await GetUserRequest(userId: 1).request()
}

// Somewhere else:
task.cancel()
```

---

## Advanced Usage

### Configuration

Global configuration lives in the `Harbor` enum, isolated to `@HRequestManagerActor`, so every setter is called with `await`.

```swift
// Headers sent with every request
await Harbor.setDefaultHeaderParameters(["X-Client-Version": "1.0.0"])

// Idle timeout per request (default 15 seconds). A request can override it with `timeoutInterval`.
await Harbor.setDefaultTimeoutInterval(30)

// Maximum duration of a whole transfer in sessions built by Harbor (default nil: system default of 7 days)
await Harbor.setDefaultResourceTimeoutInterval(300)

// Let requests use the shared cookie storage (default false)
await Harbor.setHTTPShouldHandleCookies(true)
```

Harbor builds its own `URLSession`s and keeps up to four of them alive, one per cache/cookie configuration, so connections are reused. They are rebuilt when a session-affecting setting (timeouts, cookies, mTLS, SSL pinning) changes.

**Connectivity:** a request fails fast with `.noConnection` only when the network path is unsatisfied. In that case GET requests return a cached response instead when one is usable (a fresh entry, an entry within its `stale-if-error` window, or a `URLCache` response); other network errors fall back to `stale-if-error` content only. For `needsAuth` requests the lookup uses the credential remembered from the last successful online request for that URL, without calling the auth provider; when nothing is remembered the provider is asked for its current header. The entry stored without credentials is never served. In DEBUG and simulator builds network availability is assumed; call `await Harbor.setAssumeNetworkAvailableInDebug(false)` to exercise offline flows.

### Authentication

Harbor injects authorization headers and handles 401 refresh flows through `HAuthProviderProtocol`.

```swift
actor MyAuthProvider: HAuthProviderProtocol {
    private var token = "my-token"

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        // Returning nil sends the request without an authorization header.
        HAuthorizationHeader(key: "Authorization", value: "Bearer \(token)")
    }

    func authFailed() async {
        // Called once per request when a 401 cannot be recovered with the current header.
        // Refresh the token here; Harbor re-sends the request if the header changed.
        token = "refreshed-token"
    }
}

func configureAuth() async {
    await Harbor.setAuthProvider(MyAuthProvider())
}
```

Set `needsAuth` to `true` on the requests that must carry the header:

```swift
struct SecretData: Codable, Sendable {
    let value: String
}

struct SecureRequest: HGetRequestProtocol {
    typealias Model = SecretData
    let url = "https://api.example.com/secret"
    let needsAuth = true
}
```

On a 401, Harbor asks the provider for its current header. If it already differs from the rejected one (another request's refresh finished meanwhile), the request is sent again with it without calling `authFailed()`. Otherwise Harbor calls `authFailed()` exactly once per request (concurrent requests rejected with the same credential share a single call) and, if the provider then returns a different header, sends the request once more with it. When no re-send is possible, or the re-sent request is rejected again, the request fails with `.authNeeded`; by then `authFailed()` has been called exactly once.

Cached responses of requests with `needsAuth` are namespaced by a hash of the credential they were actually sent with, so one user never reads another user's entries. A `needsAuth` request sent without a credential (the provider returned `nil`) is neither cached nor served from cache. Replacing the provider does not delete existing entries: **call `await Harbor.clearAllCache()` on logout.** A response whose request started before `Harbor.clearAllCache()` or `Harbor.setAuthProvider(_:)` is still returned to its caller, but it is not written to the cache nor remembered for offline lookups.

### Retry Policies

Set `retryPolicy` to retry transient failures with exponential backoff and jitter.

```swift
struct Feed: Codable, Sendable {
    let items: [String]
}

struct ResilientRequest: HGetRequestProtocol {
    typealias Model = Feed
    let url = "https://api.example.com/feed"
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 3, baseDelay: 0.5)
}
```

What is retried:
- HTTP statuses in `retryableStatusCodes` (default 408, 425, 429, 500, 502, 503, 504). Other statuses such as 400, 404 or 422 return immediately.
- Transient `URLError`s (timeouts, lost connection, failed secure connection, no network, host not found or unreachable). Cancellation, certificate (`.certificate`) and malformed-URL errors, and non-network errors, are never retried.
- A `Retry-After` header on 429/503 responses (seconds or HTTP date) replaces the backoff when it is at most `HRetryPolicy.maxDelay` (60 seconds). A longer `Retry-After` is not waited for: the request returns `.api(429/503)` immediately.
- POST and PATCH are not idempotent, so they are only retried after a failure that happened before the request reached the server (host not found, connection refused, no network), unless you opt in with `retryNonIdempotentRequests: true`.

```swift
struct SubmitOrderRequest: HPostRequestProtocol {
    let url = "https://api.example.com/orders"
    var bodyParameters: [String: Any]? { ["sku": "A-1"] }
    // The endpoint is idempotent (deduplicated by the server), so 5xx responses are retried too.
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 2,
                                                  retryableStatusCodes: [502, 503, 504],
                                                  retryNonIdempotentRequests: true)
}
```

### Security (mTLS & SSL Pinning)

#### SSL Pinning
Pins are `base64(SHA256(SubjectPublicKeyInfo))` hashes (RSA keys of any size and EC P-256, P-384 and P-521 keys). Generate them with `Harbor.computePin(for:)` or OpenSSL:

```
openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64
```

```swift
func configurePinning() async {
    // Include a backup pin to survive key rotation.
    let pins = ["YLh1dUR9y6Kja30RrAn7JKnbQG/uEtLMkBgFF2Fuihg=", "Vjs8r4z+80wjNcr1YKepWQboSIRi63WsWXhIMN+eWys="]

    // Apply to every host
    await Harbor.setSSLPinningKeys(pins)

    // Or scope pins to specific hosts (they take precedence over the global pins)
    await Harbor.setSSLPinningKeys(pins, forHosts: ["api.example.com"])
}
```

A failed pin, a rejected client identity or a certificate-specific TLS error (untrusted, expired or unknown-root server certificate) fails the request with `HRequestError.certificate`. A generic `URLError.secureConnectionFailed` is reported as `.networkFailure` and treated as a transient failure.

#### mTLS
The client identity is extracted from a PKCS#12 archive off the actor. The password provider is called once, when the identity is extracted, and the password is not retained. Scope the identity to the hosts that request it so it is never offered to other servers.

```swift
func configureMTLS(certURL: URL) async throws {
    let mTLS = HMTLS(p12FileUrl: certURL, hosts: ["api.example.com"]) {
        "myPassword" // e.g. read it from the keychain
    }
    try await Harbor.setMTLS(mTLS) // throws HMTLSError if the identity cannot be extracted

    // To disable it again:
    // await Harbor.clearMTLS()
}
```

On macOS 15 / iOS 18 and later the identity is imported into memory only; on earlier systems `SecPKCS12Import` may persist it to the keychain.

#### Redirects
When a redirect leaves the original origin (scheme, host or port), Harbor strips credentials from the redirected request: the auth provider's header, `Authorization`, `Cookie`, `Proxy-Authorization` and the other sensitive headers.

### Custom URLSession

`Harbor.setCustomURLSession(_:)` makes Harbor use your session as-is (pass `nil` to restore the default). SSL pinning, mTLS and redirect credential stripping are implemented by Harbor's session delegate, so **they are not applied to a custom session unless it uses the delegate returned by `Harbor.makeURLSessionDelegate()`** (or your own delegate forwards to it). Harbor logs a warning when pins or mTLS are configured and the custom session bypasses them.

```swift
func configureCustomSession() async {
    // Configure pins and mTLS first: the delegate captures the configuration when it is created.
    let delegate = await Harbor.makeURLSessionDelegate()
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    await Harbor.setCustomURLSession(session)
}
```

Per-request and default timeouts still apply to a custom session (they are set on each `URLRequest`); its cache, cookie and resource-timeout settings are its own.

### Advanced Caching

By default Harbor uses `.urlCache` (`URLCache.shared` with the protocol cache policy). Switch to Harbor's custom memory + disk cache for full control:

```swift
func configureCache() async {
    let config = HCache.Configuration(
        expirationTime: .oneHour,
        maxObjectSizeInMBs: 10,
        memoryCacheCapacityInMBs: 100,
        diskCacheCapacityInMBs: 500
    )
    await Harbor.setDefaultCacheType(.custom(config))
}
```

The custom cache:
- honors `Cache-Control` (`no-store`, `no-cache`, `must-revalidate`, `max-age`, `stale-while-revalidate`, `stale-if-error`), `Expires`, `Age`, `Date` and `Vary` (Vary'd header values are stored hashed on disk); a `no-store` response, or a body larger than `maxObjectSizeInMBs`, also evicts the previous entry for that key;
- revalidates stored entries with `If-None-Match` / `If-Modified-Since` and serves the cached body on `304 Not Modified` (a 304 without a usable cached body triggers one unconditional refetch); a validator you set yourself in `headerParameters` is kept, Harbor does not inject its own, and a 304 answering it is returned to you as `.api(statusCode: 304, data:)`;
- keeps expired entries without validators while their `stale-if-error` window still allows serving them;
- ignores the shared-cache-only directives `s-maxage` and `proxy-revalidate` (it is a private cache);
- evicts least-recently-used entries when the disk capacity is exceeded;
- namespaces entries of `needsAuth` requests by credential (see [Authentication](#authentication)).

Override the cache per request with `.custom(...)`, `.urlCache(urlCache:requestCachePolicy:)` or `.disabled`:

```swift
struct CachedRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/user"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneDay))
}
```

Read or clear the cache directly:

```swift
func inspectCache() async {
    let request = GetUserRequest(userId: 1)

    // Cached ETag, if any
    let eTag = await request.cachedETag()

    // Cached model, unless the entry is stale; no network call
    let cachedUser = await request.cache()

    // Remove this request's entry
    await request.clearCache()

    // Remove everything (custom cache, URLCache.shared and configured URLCaches). Call it on logout.
    await Harbor.clearAllCache()

    print(eTag ?? "-", cachedUser?.name ?? "-")
}
```

With `.urlCache`, `cache()` and the cached element of `requestStream(source: .cacheAndRemote)` serve the stored response unless it is explicitly stale (`no-cache` / `no-store`, an elapsed `max-age` / `Expires` lifetime after `Age` and `stale-while-revalidate` are accounted for, or an elapsed `Last-Modified` heuristic when `Date` is present). Responses without freshness headers are served.

### Multipart Requests

Provide `multipartBody` with `HFormValue` values. Text fields use `.text`, files use `.file(url:mimeType:fileName:)`; file parts are streamed from a temporary file instead of being loaded into memory.

```swift
struct UploadAvatarRequest: HPostRequestProtocol {
    let imageURL: URL

    let url = "https://api.example.com/upload"
    var bodyParameters: [String: Any]? { nil }
    var multipartBody: [String: HFormValue]? {
        [
            "username": .text("Javier"),
            "avatar": .file(url: imageURL, mimeType: "image/png", fileName: "avatar.png")
        ]
    }
}
```

### Streaming Requests

`requestStream(source:)` returns an `AsyncThrowingStream` that yields the cached model and/or the remote model, each tagged with its origin. It yields at most one cached element and one remote element.

```swift
func streamUser() async {
    do {
        for try await (user, origin) in GetUserRequest(userId: 1).requestStream(source: .cacheAndRemote) {
            print("\(origin == .cache ? "Cached" : "Fresh"): \(user.name)")
        }
    } catch {
        print("Remote request failed: \(error)")
    }
}
```

Sources: `.cacheOnly` (throws `HRequestError.noCachedDataFound` on a miss), `.remoteOnly` and `.cacheAndRemote` (yields the cached value first when present, then the remote one; throws if the remote request fails). Cancelling the consuming task cancels the request.

### JSON-RPC

The `HarborJRPC` product implements JSON-RPC 2.0, including batches and notifications. Requests use the same transport as Harbor (auth provider, mTLS, pinning, logging).

```swift
import HarborJRPC

func configureRPC() async {
    await HarborJRPC.configure(url: URL(string: "https://rpc.example.com")!, jrpcVersion: "2.0")
}

struct BlockNumberRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method = "eth_blockNumber"
}

struct GetBalanceRequest: HJRPCRequestProtocol {
    typealias Model = String
    let address: String

    let method = "eth_getBalance"
    var parameters: HJRPCParams? { .positioned([address, "latest"]) }

    // JSON-RPC calls are POSTs: read-only methods must opt in to be retried after a timeout or a 5xx.
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 3, retryNonIdempotentRequests: true)
}

func readChain() async throws {
    // request() throws an HJRPCRequestError; requestResult() returns HJRPCResponse<Model> instead.
    let blockNumber = try await BlockNumberRequest().request()

    do {
        let balance = try await GetBalanceRequest(address: "0x0000000000000000000000000000000000000000").request()
        print(blockNumber, balance)
    } catch HJRPCRequestError.jrpcError(let rpcError) {
        // Error objects are surfaced even when the server answers with a 4xx/5xx status.
        print(rpcError.code, rpcError.message, rpcError.httpStatusCode ?? 200)
    }
}
```

Batches send several requests in one HTTP call. `HarborJRPC.batch(_:)` is `async throws`: it throws when the batch as a whole fails, and returns one `HJRPCBatchResponse` per response element (paired by id, results as `HJSONValue`). An empty batch returns `[]` without a network call.

```swift
func batchCalls() async throws {
    let responses = try await HarborJRPC.batch([BlockNumberRequest(), GetBalanceRequest(address: "0x0")])
    for response in responses {
        switch response {
        case .success(let id, let result):
            print(id?.description ?? "-", result)
        case .error(let id, let error):
            print(id?.description ?? "-", error.localizedDescription)
        }
    }
}
```

Other details:
- Parameters are `.named([String: any Encodable & Sendable])` or `.positioned([any Encodable & Sendable])`. A value JSON cannot represent (e.g. `Double.nan`) fails with `HJRPCRequestError.codable` instead of being sent as `null`.
- Set `endpoint: URL?` on a request to call another endpoint than the configured one.
- Notifications set `isNotification = true` and are sent with `notify()`.
- Integers beyond `Int` decode as `HJSONValue.decimal`. Their digits are exact on iOS 18 / macOS 15 and later (swift-foundation `JSONDecoder`); on earlier OS versions they may be rounded through `Double`. The same applies to big integers passed in `HJRPCParams`.

### Debugging & Logging

Harbor logs through [LogBird](https://github.com/javiermanzo/LogBird). Logging is enabled by default in DEBUG builds and disabled in release; `setLoggingEnabled(true)` turns it on in release builds too. Security warnings (such as a custom session bypassing SSL pinning) are always logged.

Requests opt into request/response logging, including a replayable cURL command, by conforming to `HDebugRequestProtocol`:

```swift
struct DebugUserRequest: HGetRequestProtocol, HDebugRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/users/1"
    let debugType: HDebugRequestType = .requestAndResponse // .none, .request, .response
}

func configureLogging() async {
    await Harbor.setLoggingEnabled(true)

    // Extend the sensitive keys (also .set, .reset, .clear)
    await Harbor.updateLogSensitiveKeys(.add(["signature", "otp"]))
}
```

Every logged value goes through one redaction policy: request and response headers, query values, path/query/body parameters, cURL commands, response bodies and `HRequestError.api` descriptions. Sensitive keys (`authorization`, `cookie`, `set-cookie`, `x-api-key`, `password`, `token`, `secret`, the auth provider's header, plus the keys configured with `updateLogSensitiveKeys(_:)`) are printed as `<redacted>`. Matching is case-insensitive and ignores separators. `await Harbor.setLogSensitiveValues(true)` disables redaction (for local debugging only).

The cURL command only includes cookies (redacted by default) when the session sends them: with Harbor's own sessions that is when `Harbor.setHTTPShouldHandleCookies(true)` is on, reading `HTTPCookieStorage.shared`; with a custom session, according to its configuration.

### Mocking

Mocks are resolved inside Harbor's request pipeline: when mocks are enabled and a mock is registered for a request type, each attempt returns the mock instead of hitting the network, still going through status handling, retries, auth and decoding. Production code needs no changes.

```swift
func registerMocks() async {
    // Mocks are on in DEBUG builds and off in release by default; turn them on or off with:
    await Harbor.setMocksEnabled(true)

    let mock = HMock(
        request: GetUserRequest.self,
        statusCode: 200,
        jsonResponse: #"{"id": 1, "name": "Mocked User"}"#,
        delay: 1.5, // simulate network latency
        headers: ["Cache-Control": "max-age=60"]
    )
    await Harbor.register(mock: mock)

    // Simulate an error
    await Harbor.register(mock: HMock(request: SecureRequest.self, statusCode: 401, error: .authNeeded))

    // Script a sequence: first a 503, then a success (the last response repeats)
    await Harbor.register(mockSequence: HMockSequence(request: ResilientRequest.self, responses: [
        .init(statusCode: 503),
        .init(statusCode: 200, jsonResponse: #"{"items": []}"#)
    ]))

    // Every mocked attempt (retries included) since the last removeAllMocks()
    let calls = await Harbor.mockCallCount(for: ResilientRequest.self)
    let registered = await Harbor.isMockRegistered(for: ResilientRequest.self)
    print(calls, registered)

    await Harbor.removeMock(for: ResilientRequest.self)

    await Harbor.removeAllMocks()
}
```

---

## AI Assistant Skills

If you use an AI coding assistant, Harbor ships documentation written for it:

- [**AGENTS.md**](AGENTS.md): root instructions with Harbor's architecture and rules.
- [**.agents/skills/harbor/SKILL.md**](.agents/skills/harbor/SKILL.md): the detailed skill, with deep dives on caching, security, architecture and testing.
- [**.agents/skills/harbor-migration-v3-to-v4/SKILL.md**](.agents/skills/harbor-migration-v3-to-v4/SKILL.md): the v3 → v4 migration guide, listing every breaking change and how to refactor it.

---

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to get started.

## License

Harbor is available under the MIT license. See the [LICENSE.md](LICENSE.md) file for more info.
