# Harbor - Context for Agents

This document gives AI agents working on this repository the context they need about the Harbor library.

## Overview
Harbor is a lightweight networking library for Swift, built for Swift 6 strict concurrency (Swift 6 language mode, iOS 15+ / macOS 14+). It relies on `async/await` and a global actor (`@HRequestManagerActor`) to provide a thread-safe environment for REST and JSON-RPC 2.0 requests.

## Architecture & Concurrency Rules

1. **Protocols, not Classes**: Requests are `Sendable` `struct`s conforming to `HGetRequestProtocol`, `HPostRequestProtocol`, `HPutRequestProtocol`, `HPatchRequestProtocol` or `HDeleteRequestProtocol`. Every requirement is get-only (`url`, `headerParameters`, `bodyParameters`, ...), so implement them as `let` constants or computed properties; a computed `bodyParameters` keeps the struct `Sendable` without `@unchecked`.
2. **Default Implementations**: The protocols provide defaults for `needsAuth` (`false`), `retryPolicy`, `pathParameters`, `headerParameters`, `queryParameters`, `cacheType`, `timeoutInterval` (all `nil`), `multipartBody` and `rawBody` (`nil`). Only `url` (and `bodyParameters` for body requests) must be provided. The body is the first non-nil of `rawBody`, `multipartBody` and `bodyParameters` (JSON); `rawBody` is sent as `application/json` unless `headerParameters` sets a `Content-Type` (header names match case-insensitively).
3. **Async/Await First, results not throws**: REST `request()` never throws. GET requests return `HResponseWithResult<Model>` (`.success(Model)` / `.error(HRequestError)`); POST/PUT/PATCH/DELETE return `HResponse` (`.success` / `.error(HRequestError)`). JSON-RPC `request()` is the exception: it is `async throws` and returns the model (`requestResult()` returns `HJRPCResponse<Model>`).
4. **Actor Isolation**: Global configuration lives in the `Harbor` enum (isolated to `@HRequestManagerActor`). Configure it with `await Harbor.setSomething(...)`. Update UI on `@MainActor` after reading configuration.
5. **No Callbacks**: Never use escaping closures or callbacks for requests. Always `await`. Cancel a request by cancelling its `Task` (it finishes with `.cancelled`).

## Core Features & Configuration

### 1. Requests
```swift
struct User: Codable, Sendable {
    let id: Int
    let name: String
}

struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let userId: Int
    let url = "https://api.example.com/users/{id}"
    var pathParameters: [String: String]? { ["id": String(userId)] }
}

struct CreateUserRequest: HPostRequestProtocol {
    let name: String
    let url = "https://api.example.com/users"
    var bodyParameters: [String: Any]? { ["name": name] }
}

func requests() async {
    switch await GetUserRequest(userId: 1).request() {
    case .success(let user): print(user.name)
    case .error(let error): print(error)
    }

    if case .error(let error) = await CreateUserRequest(name: "Jane").request() {
        print(error)
    }
}
```
Path parameters are percent-encoded (`/` → `%2F`, `..` segments rejected); query values are strictly percent-encoded (`+` → `%2B`). A body that cannot be serialized as JSON fails with `.malformedRequest(reason:)`.

### 2. Network & Configuration
```swift
func configure() async {
    await Harbor.setDefaultTimeoutInterval(30)             // per-request idle timeout (default 15s)
    await Harbor.setDefaultResourceTimeoutInterval(300)    // whole-transfer timeout of Harbor's sessions (default: system)
    await Harbor.setDefaultHeaderParameters(["X-Client-Version": "4.0.0"])

    // Custom URLSession (used as-is). Pinning, mTLS and redirect credential stripping only
    // apply if it uses Harbor's delegate, created AFTER configuring pins/mTLS:
    let delegate = await Harbor.makeURLSessionDelegate()
    await Harbor.setCustomURLSession(URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil))
    // Restore the default Harbor sessions:
    await Harbor.setCustomURLSession(nil)
}
```
Harbor caches up to 4 internally built sessions (one per cache/cookie configuration; past the limit only the least recently used one is dropped) and rebuilds them when timeouts, cookies, mTLS or pinning change; a session still used by an in-flight request is only invalidated once that request finishes. Offline (network path unsatisfied) requests fail with `.noConnection`, except GET requests with a usable cached response (fresh, `stale-if-error` or `URLCache`); for `needsAuth` GETs the lookup uses the credential remembered from the last online success for that URL without calling the provider (otherwise the provider is asked for its current header), and never the un-namespaced entry. A `needsAuth` GET sent without a credential (provider returned `nil`) is neither cached nor served from cache.

### 3. Caching
Harbor has a multi-layer cache (memory + disk, LRU) that honors `Cache-Control` (incl. `stale-while-revalidate`, `stale-if-error`), `Expires`, `Age`, `Date`, `ETag`/`Last-Modified` revalidation (304) and `Vary`. Entries of `needsAuth` requests are namespaced by a hash of the credential: call `Harbor.clearAllCache()` on logout.
```swift
struct CachedUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/me"
    let cacheType: HCache.CacheType? = .urlCache()
}

func cache() async {
    let config = HCache.Configuration(
        expirationTime: .oneHour,
        maxObjectSizeInMBs: 10,
        memoryCacheCapacityInMBs: 100,
        diskCacheCapacityInMBs: 500
    )
    await Harbor.setDefaultCacheType(.custom(config))

    // Read the cache without network (stale entries are not returned; with .urlCache a
    // response without freshness headers counts as servable)
    let cachedUser = await CachedUserRequest().cache()
    print(cachedUser?.name ?? "-")
    await Harbor.clearAllCache() // async
}
```

### 4. Security (mTLS, SSL Pinning, Redaction)
```swift
func security(certURL: URL) async throws {
    // mTLS: async password provider (not retained); scope the identity to its hosts.
    let mTLS = HMTLS(p12FileUrl: certURL, hosts: ["api.example.com"]) { "myPassword" }
    try await Harbor.setMTLS(mTLS)

    // SSL pinning uses base64(SHA256(SPKI)) hashes (RSA any size, EC P-256/P-384/P-521):
    // openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64
    await Harbor.setSSLPinningKeys(["base64(SHA256(SPKI))_hash"], forHosts: ["api.example.com"])

    // Logs redact sensitive headers, query values, body fields and cURL by default.
    await Harbor.updateLogSensitiveKeys(.add(["signature"]))
    await Harbor.setLogSensitiveValues(false) // true prints unredacted values (local debugging only)
}
```
Pin mismatches, mTLS rejections and certificate-specific `URLError`s surface as `HRequestError.certificate` (never retried); a generic `URLError.secureConnectionFailed` is `.networkFailure` and retryable as transient. Cross-origin redirects drop `Authorization`, `Cookie`, `Proxy-Authorization` and the auth provider's header.

### 5. Authentication & Retry
```swift
actor MyAuthProvider: HAuthProviderProtocol {
    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        // returning nil means "send without auth header"
        HAuthorizationHeader(key: "Authorization", value: "Bearer token")
    }
    func authFailed() async { /* refresh the token here; Harbor re-sends once if it changed */ }
}

struct FeedRequest: HGetRequestProtocol {
    typealias Model = [String]
    let url = "https://api.example.com/feed"
    let needsAuth = true
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 3)
}

func auth() async {
    await Harbor.setAuthProvider(MyAuthProvider())
}
```
- On a 401, Harbor asks for the current header: if it already differs from the rejected one (a refresh finished meanwhile), the request is re-sent with it without calling `authFailed()`. Otherwise `authFailed()` is called exactly once per request (coalesced across concurrent 401s with the same header) and the request is re-sent once if the provider returns a new header. If that is not possible, or the re-sent request is rejected again, the request fails with `.authNeeded`, with `authFailed()` called exactly once.
- `HRetryPolicy` retries `retryableStatusCodes` (default 408, 425, 429, 500, 502, 503, 504) and transient `URLError`s, with exponential backoff + jitter; `Retry-After` is honored up to 60 s (a longer value is not waited for: the request returns `.api(429/503)` immediately). Non-`URLError` failures, cancellation and `.certificate` errors are never retried. POST/PATCH are only retried for pre-connection failures unless `retryNonIdempotentRequests: true`.

### 6. JSON-RPC (HarborJRPC)
```swift
import HarborJRPC

struct BlockRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method = "eth_blockNumber"            // takes no params: `parameters` stays nil
    // JSON-RPC calls are POSTs: read-only calls opt in to retries after timeouts/5xx.
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 2, retryNonIdempotentRequests: true)
}

struct BalanceRequest: HJRPCRequestProtocol {
    typealias Model = String
    let address: String
    let method = "eth_getBalance"
    var parameters: HJRPCParams? { .positioned([address, "latest"]) }   // or .named([...])
}

func jrpc() async throws {
    await HarborJRPC.configure(url: URL(string: "https://rpc.example.com")!, jrpcVersion: "2.0")
    let block = try await BlockRequest().request()               // throws HJRPCRequestError
    let responses = try await HarborJRPC.batch([BlockRequest(), BalanceRequest(address: "0x0")]) // async throws; [] for an empty batch
    print(block, responses.count)
}
```
JSON-RPC error objects returned with a 4xx/5xx status surface as `.jrpcError` (see `HJRPCError.httpStatusCode`). `endpoint: URL?` overrides the configured URL per request. Big integers decode as `HJSONValue.decimal` (exact on iOS 18 / macOS 15+; earlier OS versions may round them through `Double`). Non-finite parameters (NaN) throw `.codable`.

### 7. Streaming & Multipart
- **Streaming**: `requestStream(source:)` returns an `AsyncThrowingStream<(response: Model, origin: HOriginType), Error>` that yields at most one cached element and one remote element (`.cacheOnly`, `.remoteOnly`, `.cacheAndRemote`).
- **Multipart**: implement `multipartBody: [String: HFormValue]?` with `.text(String)` and `.file(url:mimeType:fileName:)`; file parts are streamed from a temporary file. To send raw data, use `rawBody`.

### 8. Mocking & Testing
Mocks short-circuit inside Harbor's request pipeline (`HRequestManager`), per attempt, so status handling, retries, auth and decoding still run. They do not use `URLProtocol`.
```swift
func mocks() async {
    await Harbor.setMocksEnabled(true)
    let mock = HMock(request: GetUserRequest.self, statusCode: 200, jsonResponse: #"{"id": 1, "name": "Jane"}"#, delay: 1.5)
    await Harbor.register(mock: mock)
}
```
Mocks are on by default in DEBUG and off in release (`setMocksEnabled(true)` enables them in release). Use `HMockSequence(request:responses:)` / `Harbor.register(mockSequence:)` to script several responses, `Harbor.mockCallCount(for:)` to assert calls (every mocked attempt, retries included, since the last `removeAllMocks()`), `Harbor.isMockRegistered(for:)` and `Harbor.removeMock(for:)`. The test suite intercepts real traffic with `URLProtocol` stubs through an internal hook (`Harbor.setProtocolClasses`, `@testable import`). Real-service tests only run with `HARBOR_RUN_NETWORK_TESTS=1`.

## Example App
The repository includes an `Example/HarborExample` app showcasing every feature (GET, POST incl. `rawBody` and multipart, Caching, Streaming, JRPC, Auth with token refresh, Retry, mTLS, SSL pinning, Mocking). It is built in Swift 6 language mode (`SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`). When modifying the Example App:
- Ensure UI state uses `@State` (or `@StateObject` for classes) to prevent lifecycle reference leaks across SwiftUI render passes.
- Isolate networking calls using `Task { await ... }`. If passing closures to a `Task` inside a SwiftUI View, mark the closure as `@Sendable` to correctly detach execution from the view's implicit `@MainActor`, and read `@State` values on the main actor before handing them to the closure.
- Always verify that global configuration states (like `Harbor.mocksEnabled`) are accessed correctly without triggering Main Actor warnings.
- A custom `URLSession` (e.g. with stub `URLProtocol`s in `protocolClasses`) must be created with `delegate: await Harbor.makeURLSessionDelegate()` so pinning, mTLS and the redirect policy stay active.

## CI & Workflow
- Commits must follow Conventional Commits (e.g., `feat:`, `fix:`, `docs:`, `chore:`).
- When adding features, ensure they comply with Swift 6 strict concurrency. The library must build without warnings: CI builds the package and fails on any compiler `warning:` emitted for files under this repository's `Sources/` (warnings from dependencies are ignored).
- Always run `swift test` and `xcodebuild test` in the Example App to ensure no regressions. CI (`.github/workflows/ci.yml`) runs unit tests with coverage and the Example App tests; `lint.yml` runs SwiftLint `--strict`; `network-tests.yml` (manual/weekly) runs the real-service tests.

## Internal Deep-Dive Documentation
Harbor contains further internal documentation files mapping out specific systems. If you need deep implementation details on specific areas, you can locate them inside `.agents/skills/harbor/`:
- `architecture.md`: Request flow and actor lifecycle.
- `cache.md`: L1/L2 cache storage, freshness and ETags.
- `security.md`: How `HURLSessionDelegate` handles trust evaluation, mTLS and redirects.
- `testing.md`: Mocks (`HMock`, `HMockSequence`) and the test suite's `URLProtocol` stubs.
- `protocols.md`: Comprehensive list of all Harbor protocols.

If migrating a codebase from Harbor v3 to v4, always consult `.agents/skills/harbor-migration-v3-to-v4/SKILL.md`.
