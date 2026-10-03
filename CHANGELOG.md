# Changelog

## [Unreleased]

Fixes from the v4 review. Changes marked **[Breaking]** affect code written against the 4.0.0 notes below.

### Added
- `Harbor.makeURLSessionDelegate()` and the public `HURLSessionDelegate`, so a session passed to `Harbor.setCustomURLSession(_:)` can enforce SSL pinning, mTLS and the redirect policy. A warning is logged (even with logging disabled) when pins or mTLS are configured and the custom session bypasses them.
- `HMTLS(p12FileUrl:hosts:passwordProvider:)` and `HMTLSIdentity.hosts`: the client identity is only presented to the given hosts.
- `Harbor.setDefaultResourceTimeoutInterval(_:)` for the whole-transfer timeout of Harbor's sessions.
- `HRetryPolicy.retryableStatusCodes` (default 408, 425, 429, 500, 502, 503, 504) and `HRetryPolicy.retryNonIdempotentRequests` (default `false`).
- `HRequestError.cannotConnectToHost` and `HRequestError.unknown(Error)`, mirrored in `HJRPCRequestError`. **[Breaking]** for exhaustive `switch`es.
- `HRequestError` conforms to `Equatable`.
- `HJRPCRequestProtocol.endpoint: URL?` to send a request to another endpoint than the configured one.
- `HJRPCError.httpStatusCode`, set when a JSON-RPC error object arrives with a non-2xx status.
- `HJSONValue.decimal(Decimal)` for integers beyond `Int`. Their digits are exact on iOS 18 / macOS 15 and later (swift-foundation `JSONDecoder`); on earlier OS versions such integers may be rounded through `Double`, also when passed in `HJRPCParams`. **[Breaking]** for exhaustive `switch`es.
- `network-tests.yml` workflow (manual and weekly) running the real-service tests with `HARBOR_RUN_NETWORK_TESTS=1`.

### Changed
- `headerParameters` and `bodyParameters` are get-only protocol requirements; implement them as `let` constants or computed properties. **[Breaking]**
- Retries only cover transient failures: retryable status codes and transient `URLError`s. Other statuses (e.g. 400, 404, 422) and non-`URLError` failures are returned immediately; cancellation and certificate errors are never retried. `Retry-After` on 429/503 is honored up to `HRetryPolicy.maxDelay` (60 seconds); a longer `Retry-After` is not waited for and the request returns `.api(429/503)` immediately. POST and PATCH are only retried after pre-connection failures unless `retryNonIdempotentRequests` is `true`; this also applies to JSON-RPC calls, which are POSTs. **[Breaking]**
- `HarborJRPC.batch(_:)` is `async throws`: it throws when the batch as a whole fails, and an empty batch returns `[]` without a network call. Batched requests must share an endpoint; their headers, auth, retry policy and debug settings are merged. **[Breaking]**
- JSON-RPC error objects returned with a 4xx/5xx status surface as `HJRPCRequestError.jrpcError` instead of `.api`. **[Breaking]**
- Notifications are strict: a 2xx body that is not empty and not a JSON-RPC response throws `.codable`; a JSON-RPC error object throws `.jrpcError`.
- `URLError.cannotConnectToHost` maps to `.cannotConnectToHost` (was `.cannotFindHost`). Pinning and mTLS rejections and the certificate-specific `URLError` codes (`serverCertificateUntrusted`, `serverCertificateHasBadDate`, `serverCertificateHasUnknownRoot`, `serverCertificateNotYetValid`, `clientCertificateRejected`, `clientCertificateRequired`) map to `.certificate`; `URLError.secureConnectionFailed` maps to `.networkFailure` and is retried as a transient failure for idempotent (or opted-in) requests. **[Breaking]**
- Query values are strictly percent-encoded (`+` is sent as `%2B`) and `/` in path parameters is encoded as `%2F`.
- A body that cannot be serialized as JSON fails with `.malformedRequest(reason:)` instead of being sent empty.
- Multipart bodies with file parts are streamed from a temporary file.
- A caller-provided `If-None-Match` / `If-Modified-Since` header is kept and Harbor does not inject its own validators.
- Cached responses of `needsAuth` requests are namespaced by a hash of the credential. Call `Harbor.clearAllCache()` on logout.
- The disk cache uses a new format (version 2) with LRU eviction; entries written by earlier versions are discarded. `Vary` header values are stored hashed.
- The custom cache honors `Age`, `Date` and `stale-while-revalidate`. A `no-store` response, or a body larger than `maxObjectSizeInMBs`, evicts the previous entry for that key. `cache()` decodes through the request's `parseData(data:model:)`.
- With `.urlCache`, `cache()` and the cached element of `requestStream(source: .cacheAndRemote)` serve the stored response unless it is explicitly stale: `no-cache` / `no-store`, an elapsed `max-age` / `s-maxage` / `Expires` lifetime (after `Age` and `stale-while-revalidate`), or an elapsed `Last-Modified` heuristic when `Date` is present. Responses without freshness headers are served.
- A `304 Not Modified` without a usable cached body triggers one unconditional refetch, only when Harbor injected the validators from its custom cache. A `304` answering validators you set yourself is returned to you as `.api(statusCode: 304, data:)`.
- A cached body that a request cannot decode is a miss for that request but is no longer evicted, so request types with different models or parsers sharing a URL keep each other's entries. Such an entry is replaced by the next full response.
- 401 handling: Harbor first asks the provider for its current header (`getAuthorizationHeader()` is called at most twice per request: once to detect a rotated header and, only after `authFailed()`, once more). If it already differs from the rejected one (another request's refresh finished meanwhile), the request is re-sent with it without calling `authFailed()`. Otherwise `authFailed()` is called exactly once per request, coalesced across concurrent requests rejected with the same header, and the request is re-sent once if the provider then returns a different header. A request that ultimately fails with `.authNeeded` after a 401 has always triggered `authFailed()`, never more than once.
- Mocks are resolved per attempt, so retries and mock sequences interact as expected; decoding runs off the actor. A mock's `error` goes through the retry policy like the real failure it stands for (e.g. `.timeout` is retried for idempotent requests, `.cannotConnectToHost` for any method).
- Offline detection only blocks requests when the network path is unsatisfied; GET requests fall back to a fresh, `stale-if-error` or `URLCache` response when offline. For `needsAuth` GETs, Harbor remembers the credential namespace used by the last online request for that URL and looks that entry up without calling the auth provider; the provider is only asked when nothing is remembered, and the entry stored without credentials is never served.
- Logging redaction uses a single policy for headers, query values, body fields, cURL, response headers and `HRequestError.api` descriptions. `Harbor.setLoggingEnabled(true)` works in release builds.
- The cURL command of a debug log includes cookies (redacted by default) only when the session sends them: with Harbor's own sessions, when `Harbor.setHTTPShouldHandleCookies(true)` is on, read from `HTTPCookieStorage.shared`; with a custom session, according to its configuration.
- The PKCS#12 identity is imported into memory only on macOS 15 / iOS 18 and later.
- SSL pinning supports RSA keys of any size and EC P-521 keys.
- Per-request timeouts are set on each `URLRequest`, so they also apply to custom sessions.
- Package: LogBird dependency relaxed to `from: "2.1.0"`; the package builds in Swift 6 language mode only.
- CI: the warnings-as-errors step is a scoped check that fails on any compiler `warning:` emitted for files under this repository's `Sources/` (warnings from dependencies are ignored), instead of `-Xswiftc -warnings-as-errors`.
- Example app: builds in Swift 6 language mode; the token-refresh demo refreshes inside `authFailed()`, its custom session uses `Harbor.makeURLSessionDelegate()`, and a `rawBody` demo was added.

### Fixed
- Credentials (`Authorization`, `Cookie`, `Proxy-Authorization`, the auth provider's header and other sensitive headers) are stripped when a redirect leaves the original origin.
- Changing a session-affecting setting (or exceeding the session cache) while requests are in flight no longer risks an Objective-C exception from creating a task on an invalidated `URLSession`: sessions still in use are retired and invalidated when their last attempt ends. Past 4 configurations only the least recently used session is dropped.
- Repeated cache hits no longer schedule a disk access-time update each before the disk index is built; updates are throttled per entry.
- `HJRPCId` no longer traps when decoding fractional or out-of-range numeric ids.
- JSON-RPC parameters that JSON cannot represent (e.g. `Double.nan`) throw `.codable` instead of being sent as `null`.
- Documentation (README, AGENTS.md, AI skills) now matches the actual API.

## [4.0.0] - 2026-08-07

Changes are relative to 3.0.0.

### Added
- JSON-RPC 2.0 spec compliance including batch requests (`HarborJRPC.batch(_:)`, returning one `HJRPCBatchResponse` per response element), notifications (`isNotification` and `notify()`), typed parameters (`HJRPCParams`), explicit request ids (`requestID: HJRPCId?`) and explicit-null result handling.
- Public `HJRPCConfig`, `HJRPCResult`, `HJRPCError`, `HJRPCId`, `HJSONValue`, `HJRPCStandardCode`, `HJRPCBatchResponse` and `HJRPCConfigurationError` types for JSON-RPC.
- `HarborJRPC.setURL(URL)` and `HarborJRPC.configure(url:jrpcVersion:)` for global JSON-RPC setup.
- Multi-layer cache (memory + disk) `HCache`, with `HCache.Configuration` (`expirationTime`, `maxObjectSizeInMBs`, `memoryCacheCapacityInMBs`, `diskCacheCapacityInMBs`; values below 1 MB are clamped to 1), the `.urlCache`, `.custom` and `.disabled` cache types (`Harbor.setDefaultCacheType(_:)` and the per-request `cacheType`), and `cache()`, `cachedETag()` and `clearCache()` on GET requests (both work with `.custom` and `.urlCache`). The custom cache honors `Cache-Control`, `Expires` and `Vary` (case-insensitive header lookup), sends stored validators as `If-None-Match` / `If-Modified-Since` and serves the cached body on `304 Not Modified`, refreshing the entry. Expired and outdated files are cleaned up in the background.
- `Harbor.clearAllCache()` (`async`), which clears the custom cache, `URLCache.shared` and the `URLCache` of the configured `.urlCache` default type / custom session.
- `requestStream(source:)` on GET requests: an `AsyncThrowingStream` that yields the cached model and/or the remote model (at most one of each), tagged with their origin. It throws if the remote request fails, even after yielding a cached value.
- `multipartBody: [String: HFormValue]?` on body requests (`.text(String)`, `.file(url:mimeType:fileName:)`), taking precedence over `bodyParameters`.
- `rawBody: Data?` on body requests to send pre-encoded data as-is.
- Per-request `timeoutInterval: TimeInterval?`, and `Harbor.setDefaultTimeoutInterval(_:)` for the default.
- `HRetryPolicy` (exponential backoff with jitter) and the `retryPolicy: HRetryPolicy?` request requirement.
- Default implementations for request protocol properties (`needsAuth`, `retryPolicy`, `pathParameters`, `headerParameters`, `queryParameters`, `timeoutInterval`, `bodyType`, `multipartBody`, `rawBody`, `cacheType`).
- mTLS: `HMTLS` with an `async throws` password provider, `HMTLSIdentity` sending the full certificate chain, `HMTLSError`, and `Harbor.clearMTLS()`.
- SSL pinning: per-host pins via `Harbor.setSSLPinningKeys(_:forHosts:)` and `Harbor.computePin(for:)` to generate `base64(SHA256(SPKI))` pins from certificates.
- `Harbor.setCustomURLSession(nil)` restores Harbor's own sessions. The sessions Harbor builds itself are cached and reused (up to 4, one per cache/cookie configuration) and rebuilt when a session-affecting setting changes; requests with `.custom` / `.disabled` cache are isolated from `URLCache.shared`.
- Connectivity: `Harbor.stopNetworkMonitor()` and `Harbor.setAssumeNetworkAvailableInDebug(_:)`.
- Logging: `Harbor.setLoggingEnabled(_:)`, automatic sensitive data redaction in debug logs, `Harbor.setLogSensitiveHeaders(_ enabled: Bool)` to opt out of it and `Harbor.loggingSensitiveKeys(_:)` to configure the sensitive keys. `LogBird` 2.1.0 is integrated behind the internal `HLogger` facade, and logging is disabled by default in release builds.
- Error cases: `HRequestError.certificate`, `.noCachedDataFound` and `.networkFailure(URLError)`; `HJRPCRequestError.certificate`, `.noCachedDataFound`, `.networkFailure`, `.invalidResponse` and `.idMismatch`.
- Mocks: `HMock.headers` to simulate response headers, `HMockSequence` and `Harbor.registerMockSequence(_:)` to script one response per attempt, `Harbor.mockCallCount(for:)`, `Harbor.isMockRegistered(_:)`, `Harbor.setMocksEnabled(_:)` and `Harbor.mocksEnabled`.
- `Harbor.setHTTPShouldHandleCookies(_:)` to handle session-level cookies.
- Harbor AI skill documentation (`AGENTS.md`, `.agents/skills/`).

### Changed
- `HJRPCRequestProtocol.parameters` is now the typed `HJRPCParams` enum (`.named` / `.positioned`) instead of `[String: Any]`. **[Breaking]**
- `HJRPCRequestProtocol.request()` now throws directly instead of returning an `HJRPCResponse`. Use `requestResult()` for the old non-throwing behavior. **[Breaking]**
- `Harbor.setMTLS(_:)` is now `async throws` and takes the new `HMTLS` type (`HmTLS` remains as a typealias; `init(p12FileUrl:password:)` is deprecated). The password provider is `@Sendable () async throws -> String`. **[Breaking]**
- `Harbor.setSSlPinningSHA256(String?)` was replaced by `Harbor.setSSLPinningKeys([String]?)` and `setSSLPinningKeys(_:forHosts:)`. Pins must be `base64(SHA256(SPKI))`; old raw-key pins never match. **[Breaking]**
- `HAuthProviderProtocol.getAuthorizationHeader()` now returns `HAuthorizationHeader?` instead of a non-optional; returning `nil` sends the request without an authorization header. **[Breaking]**
- Error cases were renamed for brevity (`apiError` → `api`, `codableError` → `codable`, `noConnectionError` → `noConnection`, `malformedRequestError` → `malformedRequest(reason:)`, `timeoutError` → `timeout`). **[Breaking]**
- `retries: Int?` was replaced by `retryPolicy: HRetryPolicy?` on `HRequestBaseRequestProtocol` and `HJRPCRequestProtocol`. **[Breaking]**
- `HJRPCRequestProtocol.headers` and `HDebugRequestProtocol.debugType` are now get-only; `debugType` defaults to `.requestAndResponse`. **[Breaking]**
- `HarborJRPC.setURL(String)` now throws `HJRPCConfigurationError.invalidURL`; `HarborJRPC.setURL(URL)` and `configure(url:jrpcVersion:)` take a `URL`. **[Breaking]**
- Harbor is distributed through Swift Package Manager only; the CocoaPods podspec was removed. **[Breaking]**
- `Harbor.setCustomURLSession(_:)` takes an optional `URLSession` and uses it as-is.
- Migrated network monitoring from SystemConfiguration to `NWPathMonitor` for reliable offline detection.
- Migrated SHA256 from CommonCrypto to `CryptoKit`.
- Debug logging is enabled by default in DEBUG builds and disabled in RELEASE; the gate is encapsulated in `HLogger`.
- Harbor no longer registers its own sensitive keys globally in LogBird.
- `HJRPCRequestError` conforms to `LocalizedError` with human-readable descriptions.

### Fixed
- Path and query parameters are now properly percent-encoded to prevent traversal/injection vulnerabilities.
- SSL Pinning hashes now strictly match the `SubjectPublicKeyInfo (SPKI)` format (aligning with OpenSSL standards) instead of raw key bytes.
- Malformed SSL pins are warned about and ignored during validation.
- `HMTLS` properly attaches intermediate certificates from the PKCS#12 archive, and PKCS#12 parsing failures are reported through `HMTLSError` instead of silently disabling mTLS.
- Sensitive keys now apply to Harbor's debug logger properly.
- Removed global LogBird mutation side effect from `HConfig.init()`; redaction is now owned by `HLogger`.
- SSL pinning exact hash comparison and trust evaluation logging.
- `generateCurl` and the structured request debug log no longer leak credentials: sensitive headers and cookies are redacted as `<redacted>` by default.
- `generateCurl` reads cookies and additional headers from Harbor's actual `URLSession` instead of `URLSession.shared`.
- False `.noConnection` on the first request in Release builds.
- Auth header injection and the 401 retry flow no longer mutate the caller's request object: the authorization header is applied to the built `URLRequest`.

### Removed
- Removed internal tracking of custom `URLSession` cache configurations in favor of explicit session handling.

### Pre-release notes (4.0.0 betas)
Changes that only affect code written against a 4.0.0 pre-release; 3.0.0 had none of these APIs.
- `TimeInterval.none` was renamed to `TimeInterval.noExpiration`.
- `Harbor.setSSlPinningKeys(_:)` (lowercase `l`) was renamed to `Harbor.setSSLPinningKeys(_:)`; a deprecated shim forwards to the new name.
- `Harbor.clearAllCache()` became `async` and also clears `URLCache.shared` and the configured `URLCache`s.
- `requestStream` throws if the remote request fails, even after yielding a cached value.
- `cachedETag()` also works with `.urlCache`; `clearCache()` falls back to the global default cache type when the request does not specify one; `clearCache` uses the proper `URLRequest` for `URLCache`; 304 handling in the custom cache was fixed.

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
