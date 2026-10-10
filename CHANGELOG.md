# Changelog

## [Unreleased]

## [4.0.0] - Unreleased

Upgrading from 3.0.0: items tagged **[Breaking]** need code changes. See the [migration guide](.agents/skills/harbor-migration-v3-to-v4/SKILL.md).

### Added

**Requests**
- `multipartBody: [String: HFormValue]?` (`.text(String)`, `.file(url:mimeType:fileName:)`) and `rawBody: Data?` on body requests. The body is the first non-nil of `rawBody`, `multipartBody` and `bodyParameters` (JSON). File parts are streamed from a temporary file. `rawBody` is sent as `application/json` unless `headerParameters` sets a `Content-Type` (header names match case-insensitively).
- Per-request `timeoutInterval: TimeInterval?` with `Harbor.setDefaultTimeoutInterval(_:)`, and `Harbor.setDefaultResourceTimeoutInterval(_:)` for the whole-transfer timeout of Harbor's sessions. Timeouts are set on each `URLRequest`, so they also apply to custom sessions.
- `HRetryPolicy` (exponential backoff with jitter) and the `retryPolicy: HRetryPolicy?` request requirement. It retries `retryableStatusCodes` (default 408, 425, 429, 500, 502, 503, 504) and transient `URLError`s; other statuses, non-`URLError` failures, cancellation and certificate errors are never retried. `Retry-After` on 429/503 is honored up to `HRetryPolicy.maxDelay` (60 s); a longer value is not waited for and the request returns `.api` immediately. POST and PATCH (and therefore JSON-RPC calls) are only retried after pre-connection failures unless `retryNonIdempotentRequests` is `true`.
- Default implementations for the optional request properties (`needsAuth`, `retryPolicy`, `pathParameters`, `headerParameters`, `queryParameters`, `timeoutInterval`, `multipartBody`, `rawBody`, `cacheType`).
- `HRequestError` conforms to `LocalizedError` and `Equatable`, and has new cases `certificate`, `noCachedDataFound`, `networkFailure(URLError)`, `cannotConnectToHost` and `unknown(Error)`, mirrored in `HJRPCRequestError`. **[Breaking]** for exhaustive `switch`es.
- `Harbor.setHTTPShouldHandleCookies(_:)` for session-level cookie handling.
- `requestStream(source:)` on GET requests: an `AsyncThrowingStream` that yields at most one cached and one remote model (`HRequestSource`), each tagged with its `HOriginType`. A cached copy that stood in for the network (offline, or `stale-if-error`) is tagged `.cache` and yielded once. It throws if the remote request fails, even after yielding a cached value.

**Caching**
- Multi-layer cache (memory + disk, LRU) `HCache` with `HCache.Configuration` (`expirationTime`, `maxObjectSizeInMBs`, `memoryCacheCapacityInMBs`, `diskCacheCapacityInMBs`; values below 1 MB are clamped to 1) and the `.urlCache`, `.custom` and `.disabled` types, set with `Harbor.setDefaultCacheType(_:)` or the per-request `cacheType`.
- GET requests gain `cache()`, `cachedETag()` and `clearCache()` (all work with `.custom` and `.urlCache`), and `shouldCache(statusCode:)` (default `true`) to keep a non-final success such as `202 Accepted` out of the cache.
- The custom cache honors `Cache-Control` (including `stale-while-revalidate` and `stale-if-error`), `Expires`, `Age`, `Date` and `Vary`; private-cache semantics apply (`s-maxage` and `proxy-revalidate` are ignored). It revalidates with `If-None-Match` / `If-Modified-Since` and serves the cached body on `304 Not Modified`; validators you set yourself are kept and a `304` answering them is returned as `.api(statusCode: 304, data:)`. Expired and outdated files are cleaned up in the background.
- `Harbor.clearAllCache()` (`async`) clears the custom cache, `URLCache.shared` and the `URLCache` of the configured `.urlCache` type or custom session. A response whose request started before `clearAllCache()` or `setAuthProvider(_:)` is returned but not cached.
- Cached responses of `needsAuth` requests are namespaced by a hash of the credential they were sent with; call `Harbor.clearAllCache()` on logout. A `needsAuth` request sent without a credential is neither cached nor served from cache.
- Offline, GET requests fall back to a fresh, `stale-if-error` or `URLCache` response; other requests fail with `.noConnection` only when the network path is unsatisfied. `Harbor.setAssumeNetworkAvailableInDebug(_:)` skips the check in DEBUG builds.

**Security**
- `HMTLS(p12FileUrl:hosts:passwordProvider:)` with an `async throws` password provider; the identity is sent with its full certificate chain and only to the given hosts. Failures are reported through `HMTLSError`. `Harbor.clearMTLS()` removes it.
- SSL pinning with per-host pins (`Harbor.setSSLPinningKeys(_:forHosts:)`) using `base64(SHA256(SPKI))` hashes (RSA of any size, EC P-256/P-384/P-521), and `Harbor.computePin(for:)` to generate them from a certificate.
- `Harbor.makeURLSessionDelegate()` and `HURLSessionDelegate`, so a session passed to `Harbor.setCustomURLSession(_:)` can enforce pinning, mTLS and the redirect policy. A warning is logged, even with logging disabled, when pins or mTLS are configured and the custom session bypasses them.
- `Harbor.setCustomURLSession(nil)` restores Harbor's own sessions, which are cached and reused (up to 4, one per cache/cookie configuration) and rebuilt when a session-affecting setting changes.

**Logging**
- `Harbor.setLoggingEnabled(_:)` (works in release builds), `Harbor.updateLogSensitiveKeys(_:)` and `Harbor.setLogSensitiveValues(_:)`. Sensitive values are redacted by default in headers, query values, body fields, cURL commands, response headers and `HRequestError.api` descriptions. Logging is on by default in DEBUG builds and off in release. `LogBird` 2.1.0 is integrated behind an internal `HLogger`.
- The cURL command of a debug log includes cookies (redacted by default) only when the session actually sends them.

**JSON-RPC**
- Full JSON-RPC 2.0 support: batches (`HarborJRPC.batch(_:)`, one `HJRPCBatchResponse` per response element), notifications (`isNotification`, `notify()`), typed parameters (`HJRPCParams`, `.named` / `.positioned`), explicit request ids (`requestID: HJRPCId?`) and explicit-null results. Parameters JSON cannot represent (e.g. `Double.nan`) throw `.codable`.
- `HarborJRPC.configure(url:jrpcVersion:)` for global setup, and `HJRPCRequestProtocol.endpoint: URL?` to send a request to another endpoint.
- `requestResult()` returns the non-throwing `HJRPCResponse`.
- Public `HJRPCError` (with `httpStatusCode`, set when an error object arrives with a non-2xx status), `HJRPCId`, `HJSONValue`, `HJRPCStandardCode` and `HJRPCBatchResponse`. `HJSONValue.decimal(Decimal)` carries integers beyond `Int`: exact on iOS 18 / macOS 15 and later, possibly rounded through `Double` on earlier OS versions (also in `HJRPCParams`).
- `HJRPCRequestError` conforms to `LocalizedError` and has new cases `certificate`, `networkFailure`, `invalidResponse` and `idMismatch`.
- Notifications are strict: a non-empty 2xx body that is not a JSON-RPC response throws `.codable`, and an error object throws `.jrpcError`.

**Mocking**
- `HMock.headers`, `HMockSequence` with `Harbor.register(mockSequence:)` to script one response per attempt, `Harbor.mockCallCount(for:)` (every mocked attempt, retries included), `Harbor.isMockRegistered(for:)`, `Harbor.removeMock(for:)`, `Harbor.setMocksEnabled(_:)` and `Harbor.mocksEnabled`.

**Package and docs**
- AI agent documentation (`AGENTS.md`, `.agents/skills/`, including the v3 to v4 migration skill).
- `network-tests.yml` workflow (manual and weekly) running the real-service tests with `HARBOR_RUN_NETWORK_TESTS=1`.

### Changed

**Requests and errors**
- `headerParameters`, `bodyParameters`, `retryPolicy` and the other request requirements are get-only; implement them as `let` constants or computed properties. `HDebugRequestProtocol.debugType` is get-only and defaults to `.requestAndResponse`. **[Breaking]**
- `retries: Int?` is replaced by `retryPolicy: HRetryPolicy?` on all request protocols. **[Breaking]**
- Error cases are renamed: `apiError` to `api`, `codableError` to `codable`, `noConnectionError` to `noConnection`, `malformedRequestError` to `malformedRequest(reason:)`, `timeoutError` to `timeout`. **[Breaking]**
- Error mapping: `URLError.cannotConnectToHost` maps to `.cannotConnectToHost` (was `.cannotFindHost`); pinning and mTLS rejections and certificate-specific `URLError`s map to `.certificate`; `URLError.secureConnectionFailed` maps to `.networkFailure` and is retried as transient. **[Breaking]**
- `HAuthProviderProtocol.getAuthorizationHeader()` returns `HAuthorizationHeader?`; `nil` sends the request without an authorization header. **[Breaking]**
- On a `401`, Harbor re-sends the request with the provider's current header without calling `authFailed()` when it already differs from the rejected one; otherwise `authFailed()` is called once per request (coalesced across concurrent requests) and the request is re-sent once if the header changed. A request that still fails with `.authNeeded` has always triggered `authFailed()`.
- `Harbor.setCustomURLSession(_:)` takes an optional `URLSession` and uses it as-is.
- Mocks are resolved per attempt (retries and sequences interact as expected), and a mock's `error` goes through the retry policy like the real failure. `Harbor.setMocksEnabled(_:)` replaces `setMocksOnlyInDebug(_:)`: mocks are on by default in DEBUG and off in release, and `setMocksEnabled(true)` enables them in release builds. `Harbor.remove(mock:)` is now `Harbor.removeMock(for:)`, taking the request type. **[Breaking]**
- Network monitoring uses `NWPathMonitor` and SHA256 uses `CryptoKit`.

**Security**
- `Harbor.setMTLS(_:)` is `async throws` and takes `HMTLS(p12FileUrl:hosts:passwordProvider:)`, which replaces `HmTLS` and `init(p12FileUrl:password:)`. The PKCS#12 identity is imported into memory only (on macOS 14 and earlier `SecPKCS12Import` has no in-memory option and persists it to the login keychain). **[Breaking]**
- `Harbor.setSSlPinningSHA256(String?)` is replaced by `Harbor.setSSLPinningKeys([String]?)`. Pins must be `base64(SHA256(SPKI))`; old raw-key pins never match. **[Breaking]**

**JSON-RPC**
- `HarborJRPC` is an enum; `setURL(_:)` and `setJRPCVersion(_:)` are replaced by `configure(url:jrpcVersion:)`. **[Breaking]**
- `HJRPCRequestProtocol.parameters` is the typed `HJRPCParams?` instead of `[String: Any]?`, and `headers` is renamed `headerParameters`. **[Breaking]**
- `HJRPCRequestProtocol.request()` is `async throws` and returns the model; use `requestResult()` for the previous `HJRPCResponse`. **[Breaking]**
- `HarborJRPC.batch(_:)` is `async throws` (an empty batch returns `[]` without a network call); batched requests must share an endpoint, and their headers, auth, retry policy and debug settings are merged. **[Breaking]**
- JSON-RPC error objects returned with a 4xx/5xx status surface as `.jrpcError` instead of `.api`. **[Breaking]**

**Package**
- The LogBird dependency is `from: "2.1.0"` (was exactly 1.0.0), and the package builds in Swift 6 language mode only. **[Breaking]** for projects still on LogBird 1.x.

### Fixed
- Path and query parameters are percent-encoded (`+` is sent as `%2B`, `/` in path parameters as `%2F`, `..` path segments are rejected), closing a traversal/injection hole.
- A body that cannot be serialized as JSON fails with `.malformedRequest(reason:)` instead of being sent empty.
- Credentials (`Authorization`, `Cookie`, `Proxy-Authorization`, the auth provider's header) are stripped when a redirect leaves the original origin.
- SSL pin comparison matches the `SubjectPublicKeyInfo` hash format used by OpenSSL instead of raw key bytes; malformed pins are warned about and ignored.
- mTLS attaches intermediate certificates from the PKCS#12 archive, and PKCS#12 parsing failures are reported through `HMTLSError` instead of silently disabling mTLS.
- Debug logs and cURL commands no longer leak credentials, and Harbor no longer mutates LogBird's global sensitive keys. cURL reads cookies and headers from Harbor's actual `URLSession` instead of `URLSession.shared`.
- False `.noConnection` on the first request in release builds.
- Auth header injection and the 401 retry no longer mutate the caller's request object.

### Removed
- `bodyType` and `HRequestDataType`: send multipart through `multipartBody`. **[Breaking]**
- `HRequestError.invalidRequest`, which was never produced. **[Breaking]** for exhaustive `switch`es.
- CocoaPods support: Harbor is distributed through Swift Package Manager only. **[Breaking]**

---

## [3.0.0] - 2024-12-25

### Added
- Implemented LogBird for structured logging (#35).

### Changed
- Moved canceled response case to an error case (#34). **[Breaking]**

---

## [2.0.0] - 2024-11-13

### Added
- Swift 6 `Sendable` compatibility and single `URLSession` enforcement between calls.
- Mock requests functionality for testing.
- Custom `URLSession` configuration support.

### Changed
- Updated repository badges.
- Updated `README.md` documenting the configuration of a custom `URLSession`.

---

## [1.0.1] - 2024-10-28

### Fixed
- Corrected how custom headers are set.
- Set `authFailed` method as `async` to handle it in a safe way.
- Retry request when it receives a 401 status code if new credentials are available.

---

## [1.0.0] - 2024-08-29

### Added
- Default Header Parameters implementation.
- Separated the Service Protocol into different protocols for each HTTP Method.
- Centralized configuration.
- Unit tests.
- mTLS certificate challenge handling.
- mTLS documentation and Table of Contents.
- SSL Pinning support.
- JSON-RPC support.
- Request retry functionality.

### Changed
- Updated error cases.
- Updated Auth Provider.
- Renamed service to request.
- Swift 6 Compatibility improvements.

### Fixed
- `hasNewAuthorizationHeader` issue.
- Debug protocol using JRPC protocol.
- Improved codable error handling.

---

## [0.1.2] - 2024-03-25

### Fixed
- Fixed `compositeUrl` generation.

---

## [0.1.1] - 2024-02-16

### Added
- First release.
