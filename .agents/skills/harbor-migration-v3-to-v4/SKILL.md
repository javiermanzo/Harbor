---
name: harbor-migration-v3-to-v4
description: Use when upgrading a project from Harbor 3.x to 4.0.0, or when fixing compile errors and behavior changes after the upgrade (retries, HmTLS, setSSlPinningSHA256, apiError, HJRPCRequestError, setURL, remove(mock:), bodyType, HJRPC headers). Lists every breaking change with before/after code. Not for writing new Harbor code (use the harbor skill).
---

# Harbor v3 to v4 migration

Work through the sections in order, then build. Harbor 4 needs a Swift 6.0 toolchain (Xcode 16+) and iOS 15+ / macOS 14+, is distributed through Swift Package Manager only (the CocoaPods podspec was removed) and builds in Swift 6 language mode only.

Code blocks that start with `// v3` show old code and don't compile against v4. Every other block compiles against v4. For the full API afterwards, see the `harbor` skill (`../harbor/SKILL.md`).

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

Retry semantics changed too: v4 retries only transient failures (retryable status codes and transient `URLError`s) with exponential backoff and jitter, and POST/PATCH (so every JSON-RPC call) are retried only after pre-connection failures unless `retryNonIdempotentRequests: true`. Details: `../harbor/protocols.md` (`HRetryPolicy`).

## 2. Get-only request properties

**v3:** `headerParameters`, `bodyType`, `bodyParameters` (REST) and `retries`, `headers`, `parameters` (JSON-RPC) were `{ get set }`.
**v4:** every requirement is `{ get }`, and most have defaults (`needsAuth`, `retryPolicy`, `pathParameters`, `headerParameters`, `queryParameters`, `cacheType`, `timeoutInterval`, `multipartBody`, `rawBody`). Only `url` (and `Model` for GET, `bodyParameters` for body requests) is required. The JSON-RPC `headers` requirement is now `headerParameters` (section 12). `bodyType` and `HRequestDataType` were removed (section 9).

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

The 401 flow is also stricter: keep the token refresh inside `authFailed()` and make `getAuthorizationHeader()` return the current token only. Harbor calls `authFailed()` at most once per request (see `../harbor/security.md`, Authentication). Cached responses of `needsAuth` requests are namespaced per credential: call `await Harbor.clearAllCache()` on logout.

## 4. mTLS

**v3:** `Harbor.setMTLS(HmTLS(p12FileUrl:password:))`, synchronous, optional argument.
**v4:** `try await Harbor.setMTLS(HMTLS(p12FileUrl:hosts:passwordProvider:))`, which throws `HMTLSError` (`.fileNotFound`, `.passwordProviderFailed`, `.invalidPassword`, `.invalidP12Format`, `.noIdentity`). `Harbor.clearMTLS()` replaces v3's `setMTLS(nil)`.

```swift
func migrateMTLS(p12URL: URL) async throws {
    let mTLS = HMTLS(p12FileUrl: p12URL, hosts: ["api.example.com"]) {
        "p12-password"   // async throws provider; called once, not retained
    }
    try await Harbor.setMTLS(mTLS)
}
```

The `HmTLS` type and its `init(p12FileUrl:password:)` were removed: rename `HmTLS` to `HMTLS` and pass the password through the `passwordProvider` closure. Scope the identity with `hosts:`; with `nil` (the default) it is presented to every host that asks for a client certificate.

## 5. SSL pinning

**v3:** `Harbor.setSSlPinningSHA256(String?)`, a hash of the raw public key.
**v4:** `Harbor.setSSLPinningKeys([String]?)` and `setSSLPinningKeys(_:forHosts:)` (note the capital `L`). **Pins must be `base64(SHA256(SPKI))`.** Old pins never match, so regenerate them with `Harbor.computePin(for: SecCertificate)` or OpenSSL (see `../harbor/security.md`).

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

`HRequestError` is now `Equatable` and `LocalizedError` (it was a plain `Error`).

| v3 | v4 |
|---|---|
| `.apiError(statusCode:data:)` | `.api(statusCode:data:)` |
| `.codableError(modelName:error:)` | `.codable(modelName:error:)` |
| `.noConnectionError` | `.noConnection` |
| `.malformedRequestError` | `.malformedRequest(reason: String?)` |
| `.timeoutError` | `.timeout` |
| `.invalidRequest` | removed (it was never produced) |
| `.invalidHttpResponse`, `.authProviderNeeded`, `.authNeeded`, `.cannotFindHost`, `.cancelled` | unchanged |
| (n/a) | `.cannotConnectToHost`, `.certificate`, `.noCachedDataFound`, `.networkFailure(URLError)`, `.unknown(Error)` |

Exhaustive `switch`es need the new cases. Pin mismatches, mTLS rejections and certificate-specific `URLError`s surface as `.certificate`; a generic `URLError.secureConnectionFailed` is `.networkFailure`. A JSON body that can't be serialized now fails with `.malformedRequest` instead of crashing.

## 8. Cache

v3 had no cache module. v4 adds `HCache.Configuration`, the `.custom`, `.urlCache()` and `.disabled` cache types (`Harbor.setDefaultCacheType(_:)`, per-request `cacheType`, default `.urlCache()`), `cache()`, `cachedETag()`, `clearCache()`, `requestStream(source:)` and the `async` `Harbor.clearAllCache()`. See `../harbor/cache.md`. Nothing needs to be migrated, but add `await Harbor.clearAllCache()` to your logout flow if you cache `needsAuth` requests or send credentials in headers.

Request URLs must now use `http` or `https` (any case); `file://`, other schemes and scheme-less URLs fail with `.malformedRequest(reason:)`.

## 9. Multipart bodies

v3 sent multipart through `bodyType = .multipart` with string `bodyParameters`. v4 removed `bodyType` and `HRequestDataType`: multipart is sent only through the typed `multipartBody: [String: HFormValue]?` requirement (`.text(String)` and `.file(url:mimeType:fileName:)`), which streams file parts from disk. Move the fields from `bodyParameters` into `multipartBody` as `.text(...)` values and return `nil` from `bodyParameters`:

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

`rawBody: Data?` is new: it sends pre-encoded bytes as-is. The body is the first non-nil of `rawBody`, `multipartBody` and `bodyParameters` (see `../harbor/protocols.md`).

## 10. Mocks

`HMock(request:statusCode:jsonResponse:error:delay:)` keeps its shape and gains `headers:`.

| v3 | v4 |
|---|---|
| `Harbor.register(mock:)` | unchanged |
| `Harbor.remove(mock: mock)` | `Harbor.removeMock(for: MyRequest.self)` |
| `Harbor.removeAllMocks()` | unchanged (also resets call counts) |
| `Harbor.setMocksOnlyInDebug(true)` | nothing: mocks are on in DEBUG and off in release by default |
| `Harbor.setMocksOnlyInDebug(false)` | `Harbor.setMocksEnabled(true)` (enables mocks in release builds too) |
| (n/a) | `Harbor.setMocksEnabled(_:)`, `Harbor.mocksEnabled` |
| (n/a) | `Harbor.register(mockSequence: HMockSequence(request:responses:))` with `HMockSequence.Response` values (e.g. `.init(statusCode: 503)`) |
| (n/a) | `Harbor.mockCallCount(for:)`, `Harbor.isMockRegistered(for:)` |

Mocks are now resolved on every attempt, so a sequence drives retries. See `../harbor/testing.md`.

## 11. Logging

`Harbor.setLoggingEnabled(_:)` (default: on in DEBUG, off in release), `Harbor.setLogSensitiveValues(_:)` and `Harbor.updateLogSensitiveKeys(_:)` are new, and logged values are redacted by default. `HDebugRequestProtocol` now inherits `Sendable`, and `debugType` is get-only with a default of `.requestAndResponse`: drop `{ get set }` conformances and declare it as a `let` (or omit it).

## 12. JSON-RPC

| v3 | v4 |
|---|---|
| `HarborJRPC.setURL(String)` | `await HarborJRPC.configure(url: URL)` (`HarborJRPC` is now an enum with only `configure(url:jrpcVersion:)` and `batch(_:)`) |
| `HarborJRPC.setJRPCVersion(String)` | `await HarborJRPC.configure(url: URL, jrpcVersion: String)` (default `"2.0"`) |
| `var parameters: [String: Any]? { get set }` | `var parameters: HJRPCParams? { get }`: a v3 dictionary becomes `.named([...])`, a list `.positioned([...])` (values must be `Encodable & Sendable`) |
| `var retries: Int? { get set }` | `var retryPolicy: HRetryPolicy? { get }` |
| `var headers: [String: String]? { get set }` | `var headerParameters: [String: String]? { get }` (same name as REST requests) |
| `request() async -> HJRPCResponse<Model>` | `request() async throws -> Model`, or `requestResult() async -> HJRPCResponse<Model>` |
| (n/a) | `notify()`, `HarborJRPC.batch(_:) async throws`, `requestID`, `isNotification`, `endpoint: URL?` |

`HJRPCRequestError` was renamed like `HRequestError`:

| v3 | v4 |
|---|---|
| `.apiError(statusCode:data:)` | `.api(statusCode:data:)` |
| `.codableError(modelName:error:)` | `.codable(modelName:error:)` |
| `.noConnectionError` | `.noConnection` |
| `.malformedRequestError` | `.malformedRequest(reason: String?)` |
| `.timeoutError` | `.timeout` |
| `.invalidRequest` | only thrown by `notify()` on a request whose `isNotification` is `false` |
| (n/a) | `.invalidResponse`, `.idMismatch(expected:actual:)`, `.cannotConnectToHost`, `.certificate`, `.networkFailure(URLError)`, `.unknown(Error)` |

`.jrpcError`, `.urlNeeded`, `.invalidHttpResponse`, `.authProviderNeeded`, `.authNeeded`, `.cannotFindHost` and `.cancelled` are unchanged.

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

Other changes: 4xx/5xx responses with a JSON-RPC error body surface as `.jrpcError` (`HJRPCError.httpStatusCode` is set). A response `id` that doesn't match the request fails with `.idMismatch`. Big integers decode as `HJSONValue.decimal`, and parameters JSON can't represent (NaN) throw `.codable`; see `../harbor/examples/jrpc.md`.

## Checklist

1. Replace `retries` with `retryPolicy` (REST and JSON-RPC).
2. Make request types plain structs with get-only properties, drop `@unchecked Sendable`, remove `bodyType`, and move `.multipart` bodies to `multipartBody`.
3. Make `getAuthorizationHeader()` return an optional (current token only, refresh in `authFailed()`), and add `clearAllCache()` to logout.
4. `try await Harbor.setMTLS(HMTLS(p12FileUrl:hosts:passwordProvider:))` instead of `HmTLS`.
5. Regenerate SSL pins as `base64(SHA256(SPKI))` and call `setSSLPinningKeys`.
6. Rename the error cases (`HRequestError` and `HJRPCRequestError`) and handle the new ones.
7. Replace `HarborJRPC.setURL` / `setJRPCVersion` with `HarborJRPC.configure(url:jrpcVersion:)`, rename JSON-RPC `headers` to `headerParameters`, wrap parameters in `HJRPCParams`, make calls `try await` and `try` `HarborJRPC.batch`.
8. Make `debugType` a get-only `let` (or drop it) in `HDebugRequestProtocol` conformances.
9. Replace `Harbor.remove(mock:)` with `Harbor.removeMock(for:)` and `setMocksOnlyInDebug(false)` with `setMocksEnabled(true)` (drop `setMocksOnlyInDebug(true)`).
10. Remove CocoaPods usage in favor of Swift Package Manager, build with Swift 6 and fix the remaining compiler errors, then run the test suite.
