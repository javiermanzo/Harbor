# Changelog

## [UNRELEASED]

### Added
- `HarborLogger` facade encapsulating LogBird (single logger instance + sensitive-key redaction) so LogBird is an internal implementation detail of Harbor (#57)
- `Harbor.loggingSensitiveKeys(_:)` taking `HLoggingSensitiveKeyAction` (`.set`, `.add`, `.reset`, `.clear`) for sensitive-key redaction configuration (#57)
- Cache system `HCache` with memory (L1) + disk (L2) storage (#39, #42)
- `HCache.CacheType`: `.urlCache` (default, automatic ETag/304), `.custom` (manual TTL and size control), `.disabled` (#52)
- Per-request `cacheType` override on GET requests (#52)
- `requestStream()` returning `AsyncThrowingStream`, with `HRequestSource` (`.remoteOnly`, `.cacheOnly`, `.cacheAndRemote`) and `HOriginType` (`.cache`, `.remote`) (#40)
- `Harbor.setDefaultCacheType()` and `Harbor.clearAllCache()` (#39, #52)
- SSL pinning with multiple keys for rotation: `Harbor.setSSlPinningKeys([String]?)` (#42)
- `Harbor.computePin(for:)` to generate SSL pins from a certificate (#56)
- mTLS identity extraction via `HMTLSIdentity` (#45)
- Configurable timeout: `Harbor.setDefaultTimeoutInterval()` (default 15s) (#54)
- `Harbor.setLoggingEnabled()` (#50)
- `Harbor.setLogSensitiveHeaders()` to control redaction of sensitive data in debug logs (#56)
- New error cases `certificate` and `noCachedDataFound`, plus `HRequestError.mapURLError(_:)` (#53)
- Default implementations for request protocol properties (`needsAuth`, `retries`, `pathParameters`, `headerParameters`, `queryParameters`, `bodyType`) (#38)
- Claude AI skill documentation (#51)
- `HCache.Configuration.diskCacheCapacityInMBs` (default 100 MB); disk capacity is enforced with LRU eviction of the oldest entries (#58)
- `HMock.headers` to simulate HTTP response headers (e.g. `Cache-Control`, `ETag`) (#58)
- New error case `HJRPCRequestError.noCachedDataFound` (#58)

### Changed
- Upgraded LogBird dependency from 1.0.0 to 2.1.0; debug logging now uses typed `LBValue` metadata, the `LBExtraMessage(key:value:)` API and LogBird's layered sensitive-key action API (#57)
- Harbor no longer registers its own sensitive keys: LogBird 2.1's expanded global defaults (`password`, `token`, `authorization`, `auth`, `secret`, `apikey`, `cookie`, `bearer`, `credentials`, `privatekey`) already cover HTTP auth fields via separator-insensitive matching. `Harbor.loggingSensitiveKeys(_:)` can still fully replace, extend, restore or clear them (previously `setSensitiveKeys` always merged `LogBird.defaultSensitiveKeys` and could not be disabled) (#57)
- Debug logging is enabled by default in DEBUG builds and disabled in RELEASE; the gate is encapsulated in `HarborLogger` (#57)
- Network monitoring migrated from SystemConfiguration to NWPathMonitor (#49)
- SHA256 migrated from CommonCrypto to CryptoKit (#47)
- Cache cleanup now runs in background (#48)
- Logging disabled by default in Release builds (#50)
- `requestStream` throws if the remote request fails even when cache is available (#46)
- Documentation updates (#37, #41)
- Custom cache now honors HTTP response directives: `Cache-Control` (`no-store`, `no-cache`, `max-age`, `s-maxage`, `must-revalidate`/`proxy-revalidate`, `stale-if-error`), `Expires` and `Vary`, with case-insensitive header lookup (HTTP/2-safe) (#58)
- Custom cache sends stored validators as `If-None-Match`/`If-Modified-Since` on GET requests; a `304 Not Modified` response serves the cached body and refreshes its expiration, even if the entry had already expired (#58)
- `HCache.Configuration.memoryCacheCapacityInMBs` is now applied to the in-memory cache; memory, disk and object-size values below 1 are clamped to 1 (#58)
- `Harbor.clearAllCache()` also clears `URLCache.shared` and the URLCache of the configured `.urlCache` default type / custom session (#58)
- `Harbor.setCustomURLSession(_:)` uses the provided session as-is; Harbor no longer caches URLSessions internally, so per-request timeout and cache-type changes always apply. Requests with `.custom`/`.disabled` cache are isolated from `URLCache.shared` (#58)
- `cachedETag()` now also works with the `.urlCache` cache type (#58)
- `clearCache()` now falls back to the global default cache type when the request does not specify one (#58)

### Fixed
- Sensitive keys now apply to Harbor's debug logger: they were previously set on `LogBird.shared` while debug logging used a separate `LogBird(subsystem:category:)` instance, so the Harbor HTTP keys never reached the logs (#57)
- Removed global LogBird mutation side effect from `HConfig.init()`; redaction is now owned by `HarborLogger` (#57)
- URL injection vulnerability: path and query parameters are now percent-encoded (#46)
- `clearCache` uses the proper URLRequest for URLCache (#52)
- 304 Not Modified handling (#52)
- SSL pinning exact hash comparison and trust evaluation logging (#42, #45)
- SSL pinning now hashes the certificate's SubjectPublicKeyInfo (SPKI) instead of the raw public key bytes, matching `openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64` (#56)
- Malformed SSL pins are warned about and ignored during validation (#56)
- mTLS now sends the certificate chain (intermediates) extracted from the P12 file (#56)
- `PKCS12.certChain` is now correctly extracted as `[SecCertificate]` (was declared `[SecTrust]?` and always `nil`) (#56)
- `generateCurl` and the structured request debug log no longer leak credentials: sensitive headers and cookies are redacted as `<redacted>` by default (#56)
- `generateCurl` reads cookies and additional headers from Harbor's actual `URLSession` instead of `URLSession.shared` (#56)
- False `.noConnection` on the first request in Release (#55)

### ⚠️ Breaking Changes
- `TimeInterval.none` renamed to `TimeInterval.noExpiration` (#58)
- `Harbor.clearAllCache()` is now `async` (#58)
- `Harbor.setSSlPinningSHA256(String?)` → `Harbor.setSSlPinningKeys([String]?)` (#42)
- SSL pinning pins must now be `base64(SHA256(SPKI))`. Pins generated from the raw public key bytes (previous behavior) will no longer match — regenerate them with `Harbor.computePin(for:)` or the OpenSSL command documented in the README (#56)
- Error cases renamed: `apiError` → `api`, `codableError` → `codable`, `noConnectionError` → `noConnection`, `malformedRequestError` → `malformedRequest`, `timeoutError` → `timeout` (#53)

## 3.0.0 - Response cases, Logging (2024-12-25)

### Changed
- Moved canceled response case to an error case (#34)

### Added
- Implemented LogBird for logging (#35)

## 2.0.0 - Swift 6 compatibility, mock requests, URL Session configuration (2024-11-13)

### Added
- Swift 6 Sendable compatibility + Single URL Session between calls
- Mock Harbor requests functionality
- Custom URLSession configuration support

### Changed
- Updated repository badges
- Updated README for the configuration of a custom URLSession

## 1.0.1 - General fixes (2024-10-28)

### Fixed
- Corrected how custom headers are set
- Set authFailed method async to handle it in a safe way
- Retry request when receives 401 statusCode if new credentials are available

## 1.0.0 - Major Release (2024-08-29)

### Added
- Default Header Parameters implementation
- Separated the Service Protocol in different protocols for each HTTP Method
- Centralized configuration
- Unit tests
- mTLS certificate challenge handling
- mTLS documentation and Table of Contents
- SSL Pinning support
- JSON-RPC support
- Request retry functionality

### Changed
- Updated error cases
- Updated Auth Provider
- Renamed service to request
- Swift 6 Compatibility improvements

### Fixed
- hasNewAuthorizationHeader issue
- Debug protocol using JRPC protocol
- Improved codable error handling

## 0.1.2 - Fix compositeUrl (2024-03-25)

### Fixed
- Fix compositeUrl

## 0.1.1 (2024-02-16)

### Added
- First release
