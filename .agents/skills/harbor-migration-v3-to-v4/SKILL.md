---
name: harbor-migration-v3-to-v4
description: Guide for migrating Harbor code from v3 to v4, addressing all breaking changes.
---

# Harbor v3 to v4 migration guide

How to migrate code that uses Harbor 3.x to the Harbor 4 API. Work through the sections in order, then build with Swift 6. Harbor 4 requires a Swift 6 toolchain and iOS 15+ / macOS 14+.

Code blocks that start with `// v3` show old code and don't compile against v4.

## 1. Retries: `retries` → `retryPolicy`

**v3:** `var retries: Int? { get set }`
**v4:** `var retryPolicy: HRetryPolicy? { get }` (default `nil`, no retries)

```swift
// v3
struct GetFeedRequest: HGetRequestProtocol {
    typealias Model = Feed
    var url = "https://api.example.com/feed"
    var retries: Int? = 3
}
```

```swift
struct Feed: Codable, Sendable {
    let items: [String]
}

struct GetFeedRequest: HGetRequestProtocol {
    typealias Model = Feed
    let url = "https://api.example.com/feed"
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 3)
}
```

**Important:** a leftover `var retries` still compiles, but nothing reads it. Search for `retries` and replace every occurrence.

Retry semantics also changed. v4 retries only transient failures: the statuses in `retryableStatusCodes` (default 408, 425, 429, 500, 502, 503, 504) and transient `URLError`s. It waits with exponential backoff and jitter, and honors `Retry-After` on 429/503 up to 60 s (a longer `Retry-After` is not waited for: the request returns `.api(429/503)` immediately). POST and PATCH (and therefore every JSON-RPC call) are retried only when `retryNonIdempotentRequests: true`, except for failures that happened before the request reached the server.

## 2. Get-only request properties

**v3:** `headerParameters`, `bodyType`, `bodyParameters` (REST) and `retries`, `headers`, `parameters` (JSON-RPC) were `{ get set }`.
**v4:** every requirement is `{ get }`, and most have defaults (`needsAuth = false`, `headerParameters = nil`, `multipartBody = nil`, `rawBody = nil`, ...). The JSON-RPC `headers` requirement is now `headerParameters` (see section 12). `bodyType` and `HRequestDataType` were removed: delete those declarations (see section 9 for multipart).

Remove the dummy setters and `@unchecked Sendable`. Expose `bodyParameters` as a computed property so the struct is `Sendable`:

```swift
// v3
final class LoginRequest: HPostRequestProtocol, @unchecked Sendable {
    var url = "https://api.example.com/login"
    var needsAuth = false
    var retries: Int? = nil
    var pathParameters: [String: String]? = nil
    var headerParameters: [String: String]? = nil
    var bodyType: HRequestDataType = .json
    var bodyParameters: [String: Any]?
}
```

```swift
struct LoginRequest: HPostRequestProtocol {
    let url = "https://api.example.com/login"
    let username: String
    let password: String

    var bodyParameters: [String: Any]? {
        ["username": username, "password": password]
    }
}
```

If code mutated a request after creating it, pass the values through the initializer instead.

## 3. `HAuthProviderProtocol` returns an optional

**v3:** `func getAuthorizationHeader() async -> HAuthorizationHeader`
**v4:** `func getAuthorizationHeader() async -> HAuthorizationHeader?`. Return `nil` to send the request without credentials.

The 401 flow is also stricter. Harbor first asks for the current header: if it already differs from the rejected one (another request's refresh finished meanwhile), the request is re-sent with it without calling `authFailed()`. Otherwise `authFailed()` is called exactly once per request (concurrent 401s that used the same header share one call) and the request is re-sent once if the header changed; if that is not possible, or the re-sent request is rejected again, the request fails with `.authNeeded`. Keep the refresh inside `authFailed()` and make `getAuthorizationHeader()` return the current token only. Auth-scoped cache entries are namespaced per credential. Call `await Harbor.clearAllCache()` on logout.

## 4. mTLS

**v3:** `Harbor.setMTLS(HmTLS(p12FileUrl:password:))`, synchronous.
**v4:** `try await Harbor.setMTLS(HMTLS(p12FileUrl:hosts:passwordProvider:))`, which throws `HMTLSError`. `Harbor.clearMTLS()` removes it (v3's `setMTLS(nil)`).

```swift
func migrateMTLS(p12URL: URL) async throws {
    let mTLS = HMTLS(p12FileUrl: p12URL, hosts: ["api.example.com"]) {
        "p12-password"   // async throws provider; called once, not retained
    }
    try await Harbor.setMTLS(mTLS)
}
```

The `HmTLS` type and its `init(p12FileUrl:password:)` were removed: rename `HmTLS` to `HMTLS` and pass the password through the `passwordProvider` closure. Scope the identity with `hosts:`. With `nil` it is presented to every host that asks for a client certificate.

## 5. SSL pinning

**v3:** `Harbor.setSSlPinningSHA256(String?)`, a hash of the raw public key.
**v4:** `Harbor.setSSLPinningKeys([String]?)` and `setSSLPinningKeys(_:forHosts:)`. **Pins must be `base64(SHA256(SPKI))`.** Old pins never match, so regenerate them with `Harbor.computePin(for:)` or OpenSSL (see `../harbor/security.md`). There is no `setSSlPinning...` (lowercase `l`) spelling in v4.

## 6. Custom URLSession

**v3:** `Harbor.setCustomURLSession(URLSession)`
**v4:** `Harbor.setCustomURLSession(URLSession?)`. Pass `nil` to restore Harbor's sessions. The session is used as-is: pinning, mTLS and cross-origin credential stripping apply only if its delegate comes from `Harbor.makeURLSessionDelegate()`.

```swift
func migrateSession() async {
    let delegate = await Harbor.makeURLSessionDelegate()
    await Harbor.setCustomURLSession(URLSession(configuration: .default, delegate: delegate, delegateQueue: nil))
}
```

## 7. Errors

| v3 | v4 |
|---|---|
| `.apiError(statusCode:data:)` | `.api(statusCode:data:)` |
| `.codableError(modelName:error:)` | `.codable(modelName:error:)` |
| `.noConnectionError` | `.noConnection` |
| `.malformedRequestError` | `.malformedRequest(reason: String?)` |
| `.timeoutError` | `.timeout` |
| `.invalidRequest` | removed (it was never produced) |
| (n/a) | `.cannotConnectToHost`, `.certificate`, `.noCachedDataFound`, `.networkFailure(URLError)`, `.unknown(Error)` |

`HRequestError` is now `Equatable` and `LocalizedError`. Switches that must be exhaustive need the new cases. Pin mismatches, mTLS rejections and certificate-specific `URLError`s surface as `.certificate`; a generic `URLError.secureConnectionFailed` is `.networkFailure`. A JSON body that can't be serialized now fails with `.malformedRequest` instead of crashing.

## 8. Cache

v3 had no cache module. v4 adds `HCache.Configuration`, the `.custom`, `.urlCache()` and `.disabled` cache types (`Harbor.setDefaultCacheType(_:)`, per-request `cacheType`), `cache()`, `cachedETag()`, `clearCache()`, `requestStream(source:)` and the `async` `Harbor.clearAllCache()`. See `../harbor/cache.md`. Nothing needs to be migrated, but add `await Harbor.clearAllCache()` to your logout flow if you enable caching for `needsAuth` requests.

## 9. Multipart bodies

v3 only supported multipart through `bodyType = .multipart` with string `bodyParameters`. v4 removed `bodyType` and `HRequestDataType`: multipart is sent only through the typed `multipartBody: [String: HFormValue]?` requirement (`.text(String)` and `.file(url:mimeType:fileName:)`), which streams file parts from disk. Move the fields from `bodyParameters` into `multipartBody` as `.text(...)` values and return `nil` from `bodyParameters`:

```swift
struct UploadAvatarRequest: HPostRequestProtocol {
    let url = "https://api.example.com/me/avatar"
    let fileURL: URL

    var bodyParameters: [String: Any]? { nil }
    var multipartBody: [String: HFormValue]? {
        ["avatar": .file(url: fileURL, mimeType: "image/jpeg", fileName: "avatar.jpg")]
    }
}
```

`rawBody: Data?` (new as well) sends pre-encoded bytes as-is, with `Content-Type: application/json` unless `headerParameters` sets a `Content-Type` (header names match case-insensitively). The body is the first non-nil of `rawBody`, `multipartBody` and `bodyParameters` (JSON).

## 10. Mocks

`HMock(request:statusCode:jsonResponse:error:delay:)` keeps its shape and gains `headers:`.

| v3 | v4 |
|---|---|
| `Harbor.register(mock:)` | `Harbor.register(mock:)` (unchanged) |
| `Harbor.remove(mock: mock)` | `Harbor.removeMock(for: MyRequest.self)` |
| `Harbor.removeAllMocks()` | `Harbor.removeAllMocks()` (also resets call counts) |
| `Harbor.setMocksOnlyInDebug(true)` | nothing: mocks are on in DEBUG and off in release by default |
| `Harbor.setMocksOnlyInDebug(false)` | `Harbor.setMocksEnabled(true)` (enables mocks in release builds too) |
| (n/a) | `Harbor.setMocksEnabled(_ enabled: Bool)`, `Harbor.mocksEnabled` |
| (n/a) | `Harbor.register(mockSequence: HMockSequence(request:responses:))` with `HMockSequence.Response` values (e.g. `.init(statusCode: 503)`) |
| (n/a) | `Harbor.mockCallCount(for:)` (every mocked attempt, retries included, since the last `removeAllMocks()`), `Harbor.isMockRegistered(for:)` |

Mocks are now resolved on every attempt, so a sequence drives retries.

## 11. Logging

`Harbor.setLoggingEnabled(_:)` (default: on in DEBUG, off in release), `Harbor.setLogSensitiveValues(_ enabled: Bool)` and `Harbor.updateLogSensitiveKeys(_:)` are new. Logged values are redacted by default. `HDebugRequestProtocol.debugType` is get-only and defaults to `.requestAndResponse`: drop `{ get set }` conformances and declare it as a `let` (or omit it).

## 12. JSON-RPC

| v3 | v4 |
|---|---|
| `HarborJRPC.setURL(String)` | `await HarborJRPC.configure(url: URL)` (`HarborJRPC` is an enum with only `configure(url:jrpcVersion:)` and `batch(_:)`) |
| `HarborJRPC.setJRPCVersion(String)` | `await HarborJRPC.configure(url: URL, jrpcVersion: String)` (default `"2.0"`) |
| `var parameters: [String: Any]? { get set }` | `var parameters: HJRPCParams? { get }` (`.named` / `.positioned`) |
| `var retries: Int? { get set }` | `var retryPolicy: HRetryPolicy? { get }` |
| `var headers: [String: String]? { get set }` | `var headerParameters: [String: String]? { get }` (same name as REST requests) |
| `request() async -> HJRPCResponse<Model>` | `request() async throws -> Model`, or `requestResult() async -> HJRPCResponse<Model>` |
| (n/a) | `notify()`, `HarborJRPC.batch(_:) async throws`, `requestID`, `isNotification`, `endpoint: URL?` |

```swift
struct BalanceRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method = "eth_getBalance"
    let parameters: HJRPCParams?
    // Read-only call sent as POST: opt in to retry after timeouts / 5xx
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 2, retryNonIdempotentRequests: true)

    init(address: String) {
        parameters = .positioned([address, "latest"])
    }
}

func migrateJRPC() async throws {
    await HarborJRPC.configure(url: URL(string: "https://rpc.example.com")!)
    let balance = try await BalanceRequest(address: "0xabc").request()
    let batch = try await HarborJRPC.batch([BalanceRequest(address: "0x1"), BalanceRequest(address: "0x2")])
    print(balance, batch.count)
}
```

Other JSON-RPC changes: 4xx/5xx responses with a JSON-RPC error body surface as `.jrpcError`, with `HJRPCError.httpStatusCode` set. A response `id` that doesn't match the request fails with `.idMismatch`. Big integers decode as `HJSONValue.decimal` (exact on iOS 18 / macOS 15 and later; earlier OS versions may round them through `Double`). Parameters JSON can't represent (NaN) throw `.codable`.

## Checklist

1. Replace `retries` with `retryPolicy` (REST and JSON-RPC).
2. Make request types plain structs with get-only properties, drop `@unchecked Sendable`, remove `bodyType`, and move `.multipart` bodies to `multipartBody`.
3. Make `getAuthorizationHeader()` return an optional (current token only, refresh in `authFailed()`), and add `clearAllCache()` to logout.
4. Await `setMTLS`, switch from `HmTLS` to `HMTLS(p12FileUrl:hosts:passwordProvider:)`.
5. Regenerate SSL pins as `base64(SHA256(SPKI))`.
6. Rename error cases and handle the new ones.
7. Replace `HarborJRPC.setURL` / `setJRPCVersion` with `HarborJRPC.configure(url:jrpcVersion:)`, rename JSON-RPC `headers` to `headerParameters`, make calls `try await`, wrap parameters in `HJRPCParams`, and `try` `HarborJRPC.batch`.
8. Make `debugType` a get-only `let` (or drop it) in `HDebugRequestProtocol` conformances.
9. Replace `Harbor.remove(mock:)` with `Harbor.removeMock(for:)` and `setMocksOnlyInDebug(false)` with `setMocksEnabled(true)` (drop `setMocksOnlyInDebug(true)`).
10. Run `swift build` and fix the remaining compiler errors. Run the test suite.
