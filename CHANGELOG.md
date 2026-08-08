# Changelog

## [4.0.0] - 2026-08-07

### Added
- JSON-RPC 2.0 spec compliance including batch requests (`HarborJRPC.batch`), notifications (`notify()`), typed parameters (`HJRPCParams`), and explicit-null result handling.
- Public `HJRPCConfig`, `HJRPCResult`, and `HJRPCError` types for JSON-RPC.
- `HarborJRPC.setURL(URL)` and `HarborJRPC.configure` methods for global JSON-RPC setup.
- Advanced multi-layer cache system (Memory + Disk) `HCache` honoring HTTP directives (`Cache-Control`, `ETag`, `Vary`) with automatic 304 handling.
- Native `AsyncThrowingStream` support via `requestStream()` to handle large payloads chunk by chunk.
- Support for `HCache.CacheType` overrides per-request via `.cacheType`.
- Cache system configurations including `.urlCache`, `.custom`, and `.disabled`.
- `HCache.Configuration.diskCacheCapacityInMBs` and `memoryCacheCapacityInMBs` configuration.
- Background cache cleanup functionality.
- mTLS identity extraction via `HMTLSIdentity` sending full certificate chains.
- Per-host SSL pinning configuration via `Harbor.setSSLPinningKeys(_:forHosts:)`.
- `Harbor.computePin(for:)` utility to generate base64 SPKI hashes from certificates.
- Configurable global timeouts via `Harbor.setDefaultTimeoutInterval`.
- Automatic sensitive data redaction in debug logs via `Harbor.setLogSensitiveHeaders`.
- Logging disabled by default in Release builds via `HarborLogger`.
- Integrated `LogBird` 2.1.0 behind a private `HarborLogger` facade.
- New error cases: `certificate`, `noCachedDataFound`, and `HRequestError.mapURLError`.
- `HJRPCRequestError.noCachedDataFound` case.
- Default implementations for request protocol properties (`needsAuth`, `retries`, `pathParameters`, `headerParameters`, `queryParameters`, `bodyType`, `cacheType`).
- `rawBody` property in `HRequestWithBodyProtocol` to send raw `Data`.
- `HMock.headers` to simulate HTTP response headers in mocks.
- CocoaPods subspec `Harbor/JRPC`.
- Harbor Claude AI skill documentation.
- `Harbor.setHTTPShouldHandleCookies` to handle session-level cookies.

### Changed
- `HJRPCRequestProtocol.parameters` is now the typed `HJRPCParams` enum (`.named` / `.positioned`) instead of `[String: Any]`. **[Breaking]**
- `HJRPCRequestProtocol.request()` now throws directly instead of returning an `HJRPCResponse`. Use `requestResult()` for the old non-throwing behavior. **[Breaking]**
- `Harbor.setMTLS(_:)` is now `async throws` and takes the new `HMTLS` type. The password provider is also `async throws`. **[Breaking]**
- SSL Pinning strings must now be `base64(SHA256(SPKI))`. Old raw-key pins will fail. **[Breaking]**
- `HAuthProviderProtocol.getAuthorizationHeader()` now returns `HAuthorizationHeader?` instead of a non-optional; returning `nil` sends the request without an authorization header. **[Breaking]**
- `Harbor.clearAllCache()` is now `async`. **[Breaking]**
- Error cases were renamed for brevity (`apiError` → `api`, `codableError` → `codable`, `noConnectionError` → `noConnection`, `malformedRequestError` → `malformedRequest`, `timeoutError` → `timeout`). **[Breaking]**
- `TimeInterval.none` was renamed to `TimeInterval.noExpiration`. **[Breaking]**
- `Harbor.setSSlPinningSHA256(String?)` renamed to `Harbor.setSSLPinningKeys([String]?)`. **[Breaking]**
- `HmTLS` renamed to `HMTLS`. **[Breaking]**
- `HJRPCRequestProtocol.retries` and `.headers` are now get-only. **[Breaking]**
- Migrated network monitoring from SystemConfiguration to `NWPathMonitor` for reliable offline detection.
- Migrated SHA256 from CommonCrypto to `CryptoKit`.
- Debug logging is enabled by default in DEBUG builds and disabled in RELEASE; the gate is encapsulated in `HarborLogger`.
- Harbor no longer registers its own sensitive keys globally in LogBird.
- `requestStream` throws if the remote request fails even when cache is available.
- Custom cache now honors HTTP response directives: `Cache-Control`, `Expires` and `Vary`, with case-insensitive header lookup.
- Custom cache sends stored validators as `If-None-Match`/`If-Modified-Since` on GET requests; a `304 Not Modified` response serves the cached body and refreshes its expiration.
- Memory, disk and object-size values for cache capacities below 1 are clamped to 1.
- `Harbor.clearAllCache()` also clears `URLCache.shared` and the URLCache of the configured `.urlCache` default type / custom session.
- `Harbor.setCustomURLSession(_:)` now accepts an optional `URLSession` (passing `nil` restores the default session) and uses it as-is; Harbor no longer caches URLSessions internally. Requests with `.custom`/`.disabled` cache are isolated from `URLCache.shared`.
- `cachedETag()` now also works with the `.urlCache` cache type.
- `clearCache()` now falls back to the global default cache type when the request does not specify one.
- `HJRPCRequestError` conforms to `LocalizedError` with human-readable descriptions, and includes new `invalidResponse` and `idMismatch` cases.
- `HMTLS.passwordProvider` is now `@Sendable () async throws -> String` and `extractIdentity` is `async`.
- SHA256 helpers renamed for clarity: `SHA256.sha256(data:)` → `sha256Base64(data:)`, `SHA256.hash(data:)` → `sha256Data(data:)`, `String.sha256Hash` → `String.sha256Hex`.

### Fixed
- Path and query parameters are now properly percent-encoded to prevent traversal/injection vulnerabilities.
- SSL Pinning hashes now strictly match the `SubjectPublicKeyInfo (SPKI)` format (aligning with OpenSSL standards) instead of raw key bytes.
- Malformed SSL pins are warned about and ignored during validation.
- `HMTLS` properly attaches intermediate certificates from the PKCS#12 archive.
- `PKCS12.certChain` is now correctly extracted as `[SecCertificate]` (was declared `[SecTrust]?` and always `nil`).
- Sensitive keys now apply to Harbor's debug logger properly.
- Removed global LogBird mutation side effect from `HConfig.init()`; redaction is now owned by `HarborLogger`.
- `clearCache` uses the proper URLRequest for URLCache.
- 304 Not Modified handling in cache.
- SSL pinning exact hash comparison and trust evaluation logging.
- `generateCurl` and the structured request debug log no longer leak credentials: sensitive headers and cookies are redacted as `<redacted>` by default.
- `generateCurl` reads cookies and additional headers from Harbor's actual `URLSession` instead of `URLSession.shared`.
- False `.noConnection` on the first request in Release builds.
- Auth header injection and the 401 retry flow no longer mutate the caller's request object: the authorization header is applied to the built `URLRequest`.
- `PKCS12` parsing is now the throwing `PKCS12.parse(...)` with a typed `PKCS12Error` and logged failure statuses.

### Removed
- Removed internal tracking of custom `URLSession` cache configurations in favor of explicit session handling.

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
