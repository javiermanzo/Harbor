---
name: harbor
description: Use when writing, reviewing or debugging Swift code that uses the Harbor networking library (REST requests via HGetRequestProtocol/HPostRequestProtocol, HarborJRPC JSON-RPC, caching, auth providers, retry policies, SSL pinning, mTLS, mocks, debug logging).
---

# Harbor

Harbor is a protocol-oriented networking library for Swift 6 (strict concurrency, `async/await`, global actor). Requests are `Sendable` structs conforming to per-method protocols; global configuration lives on the `Harbor` enum, which is isolated to `@HRequestManagerActor`, so every configuration call is `await`ed.

Requirements: Swift 6 toolchain (tools 6.0), iOS 15+ / macOS 14+. Products: `Harbor` and `HarborJRPC`.

## Core rules

1. **Requests are structs.** Conform to `HGetRequestProtocol`, `HPostRequestProtocol`, `HPutRequestProtocol`, `HPatchRequestProtocol` or `HDeleteRequestProtocol`. Requirements such as `headerParameters` and `bodyParameters` are get-only: implement them as `let` constants or computed properties. A computed `bodyParameters: [String: Any]?` keeps the struct `Sendable` without `@unchecked`.
2. **Defaults exist.** `needsAuth` (`false`), `retryPolicy` (`nil`, no retries), `pathParameters`, `headerParameters`, `timeoutInterval`, `queryParameters`, `cacheType` (all `nil`), `bodyType` (`.json`), `multipartBody` and `rawBody` (`nil`). Override only what you need.
3. **REST requests do not throw.** For a GET, `request()` returns `HResponseWithResult<Model>` (`.success(Model)` / `.error(HRequestError)`). POST, PUT, PATCH and DELETE return `HResponse` (`.success` / `.error`). REST requests have no `requestResult()`.
4. **JSON-RPC requests throw.** `HJRPCRequestProtocol.request()` is `async throws -> Model`, and `requestResult()` returns `HJRPCResponse<Model>` without throwing.
5. **Configuration is awaited.** Call `await Harbor.setX(...)` from any context. `HRequestManagerActor` is a global actor, so hop back to `@MainActor` before updating UI.
6. **No completion handlers.** Use `async/await` everywhere.

```swift
struct User: Codable, Sendable {
    let id: Int
    let name: String
}

struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/users/{id}"
    let pathParameters: [String: String]?

    init(id: Int) {
        pathParameters = ["id": String(id)]
    }
}

struct CreateUserRequest: HPostRequestProtocol {
    let url = "https://api.example.com/users"
    let name: String

    var bodyParameters: [String: Any]? { ["name": name] }
}

func load() async {
    switch await GetUserRequest(id: 1).request() {
    case .success(let user):
        print(user.name)
    case .error(let error):
        print(error.localizedDescription)
    }

    if case .error(let error) = await CreateUserRequest(name: "Jane").request() {
        print(error)
    }
}
```

## Configuration

```swift
func configureHarbor() async {
    await Harbor.setDefaultTimeoutInterval(30)               // per-request idle timeout (default 15s)
    await Harbor.setDefaultResourceTimeoutInterval(300)      // whole-transfer limit for Harbor-built sessions (default: system, 7 days)
    await Harbor.setDefaultHeaderParameters(["X-Client-Version": "4.0.0"])
    await Harbor.setHTTPShouldHandleCookies(false)
    await Harbor.setLoggingEnabled(true)                     // default: on in DEBUG, off in release
}
```

Custom `URLSession`: Harbor uses it as-is. SSL pinning, mTLS and the cross-origin redirect policy live in Harbor's session delegate, so they only apply when the session uses the delegate from `Harbor.makeURLSessionDelegate()`. Create it after configuring pins and mTLS, because it captures the configuration at creation time. Harbor logs a security warning when pins or mTLS are configured and the custom session doesn't use its delegate.

```swift
func useCustomSession() async {
    let delegate = await Harbor.makeURLSessionDelegate()
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    await Harbor.setCustomURLSession(session)
    // Restore Harbor's own sessions:
    await Harbor.setCustomURLSession(nil)
}
```

## Retry

`retryPolicy: HRetryPolicy?` (default `nil`) controls retries. Only transient failures are retried:

- HTTP statuses in `retryableStatusCodes` (default 408, 425, 429, 500, 502, 503, 504).
- Transient `URLError`s: timeouts, lost connections, no network, host not found or unreachable.

Cancellation, certificate (`.certificate`) and bad-URL errors are never retried, and neither are errors other than `URLError`. POST and PATCH are retried only when `retryNonIdempotentRequests` is `true`. The exception is a failure that happened before the request reached the server (DNS failure, connection refused, offline), which is retried for any method. A `Retry-After` header on a 429 or 503 response is honored up to `HRetryPolicy.maxDelay` (60 s); a longer `Retry-After` is not waited for, and the request returns `.api(429/503)` immediately. Otherwise the delay is exponential backoff plus jitter.

```swift
struct FlakyRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/flaky"
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 3, baseDelay: 0.5, multiplier: 2)
}
```

## Authentication

```swift
final class TokenAuthProvider: HAuthProviderProtocol {
    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        // nil sends the request without credentials
        HAuthorizationHeader(key: "Authorization", value: "Bearer token")
    }

    func authFailed() async {
        // refresh the token here; Harbor re-sends the request once if the header changed
    }
}

func configureAuth() async {
    await Harbor.setAuthProvider(TokenAuthProvider())
}
```

Requests opt in with `let needsAuth = true`. Without a provider they fail with `.authProviderNeeded`. On a 401, Harbor asks for the current header: if it already differs from the rejected one (another request's refresh finished meanwhile), the request is re-sent with it without calling `authFailed()`. Otherwise `authFailed()` is called exactly once per request (concurrent 401s for the same header share a single call) and the request is re-sent once if the provider now returns a different header. If that is not possible, or the re-sent request is rejected again, the request fails with `.authNeeded`, and `authFailed()` has been called exactly once by then. Call `await Harbor.clearAllCache()` on logout (see Cache).

## Cache

Default cache type: `.urlCache()` (`URLCache.shared`). `.custom(HCache.Configuration)` enables Harbor's memory + disk cache. It honors `Cache-Control`, `Expires`, `Age`/`Date`, `ETag`/`Last-Modified` (304 revalidation), `Vary`, `stale-while-revalidate` and `stale-if-error`. `.disabled` turns caching off. Override the type per request with `cacheType`.

```swift
struct CachedUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/me"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneHour))
}

func cacheExamples() async {
    await Harbor.setDefaultCacheType(.custom(HCache.Configuration(expirationTime: .oneDay,
                                                                  maxObjectSizeInMBs: 10,
                                                                  memoryCacheCapacityInMBs: 100,
                                                                  diskCacheCapacityInMBs: 500)))
    let cached: User? = await CachedUserRequest().cache()   // fresh entry only, no network
    let etag = await CachedUserRequest().cachedETag()
    await CachedUserRequest().clearCache()
    await Harbor.clearAllCache()                             // also call on logout
    _ = (cached, etag)
}
```

Entries for `needsAuth` requests are namespaced by a SHA-256 digest of the authorization header, so one user never reads another user's entry. Replacing the auth provider does not delete anything, which is why `clearAllCache()` belongs in the logout flow.

## Streaming

`requestStream(source:)` (GET only) returns `AsyncThrowingStream<(response: Model, origin: HOriginType), Error>`. It is not a byte stream: it yields at most one cached element (`.cache`) and one remote element (`.remote`). Sources are `.cacheAndRemote` (default), `.cacheOnly` (throws `.noCachedDataFound` on a miss) and `.remoteOnly`.

## Multipart and raw bodies

Use `multipartBody: [String: HFormValue]?` with `.text(String)` and `.file(url:mimeType:fileName:)`. When file parts are present, the body is streamed to a temporary file and uploaded from disk. Use `rawBody: Data?` to send bytes as-is (with `Content-Type: application/json` unless you set it in `headerParameters`). If `bodyParameters` can't be serialized as JSON, the request fails with `.malformedRequest`.

## Errors

`HRequestError` is `Equatable`. Cases: `.api(statusCode:data:)`, `.invalidHttpResponse`, `.invalidRequest`, `.authProviderNeeded`, `.authNeeded`, `.codable(modelName:error:)`, `.noConnection`, `.malformedRequest(reason:)`, `.timeout`, `.cannotFindHost`, `.cannotConnectToHost`, `.cancelled`, `.certificate` (pin mismatch, mTLS rejection or a certificate-specific `URLError`; a generic `secureConnectionFailed` is `.networkFailure`), `.noCachedDataFound`, `.networkFailure(URLError)` and `.unknown(Error)`.

## Security

```swift
func configureSecurity(certURL: URL) async throws {
    await Harbor.setSSLPinningKeys(["base64(SHA256(SPKI))="], forHosts: ["api.example.com"])
    let mTLS = HMTLS(p12FileUrl: certURL, hosts: ["api.example.com"]) { "p12-password" }
    try await Harbor.setMTLS(mTLS)
    await Harbor.setLogSensitiveHeaders(false)               // false (default) = redact
    await Harbor.loggingSensitiveKeys(.add(["otp"]))
}
```

## Mocks

Mocks short-circuit inside Harbor's request manager on each attempt, before any network call. They are enabled by default in DEBUG builds.

```swift
func registerMocks() async {
    await Harbor.setMocksEnabled(true)
    await Harbor.register(mock: HMock(request: GetUserRequest.self,
                                      statusCode: 200,
                                      jsonResponse: #"{"id":1,"name":"Mock"}"#,
                                      delay: 0.5))
}
```

## JSON-RPC

```swift
struct BlockNumberRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method = "eth_blockNumber"            // takes no params: `parameters` stays nil
    // JSON-RPC is POST: opt in to retry read-only calls after timeouts/5xx.
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 2, retryNonIdempotentRequests: true)
}

struct GetBalanceRequest: HJRPCRequestProtocol {
    typealias Model = String
    let address: String
    let method = "eth_getBalance"
    var parameters: HJRPCParams? { .positioned([address, "latest"]) }
}

func jsonRPC() async throws {
    await HarborJRPC.configure(url: URL(string: "https://rpc.example.com")!, jrpcVersion: "2.0")
    let block = try await BlockNumberRequest().request()
    let responses = try await HarborJRPC.batch([BlockNumberRequest(), GetBalanceRequest(address: "0x0")])
    print(block, responses.count)
}
```

Integers beyond `Int` decode as `HJSONValue.decimal`, exact on iOS 18 / macOS 15 and later; earlier OS versions may round them through `Double`.

## Deep dives

- `architecture.md`: request flow, actor model and session management.
- `protocols.md`: every request protocol, property and response type.
- `cache.md`: custom cache, HTTP semantics, keys, disk format and offline behavior.
- `security.md`: SSL pinning, mTLS, redirects, custom sessions, auth and log redaction.
- `testing.md`: mocks, sequences and testing patterns.
- `examples/basic.md`, `examples/advanced.md`, `examples/jrpc.md`: copy-ready examples.

When migrating from Harbor v3, read `../harbor-migration-v3-to-v4/SKILL.md`.
