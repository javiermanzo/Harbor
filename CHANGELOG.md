# Changelog

## [UNRELEASED]

### Added
- Cache system `HCache` with memory (L1) + disk (L2) storage (#39, #42)
- `HCache.CacheType`: `.urlCache` (default, automatic ETag/304), `.custom` (manual TTL and size control), `.disabled` (#52)
- Per-request `cacheType` override on GET requests (#52)
- `requestStream()` returning `AsyncThrowingStream`, with `HRequestSource` (`.remoteOnly`, `.cacheOnly`, `.cacheAndRemote`) and `HOriginType` (`.cache`, `.remote`) (#40)
- `Harbor.setDefaultCacheType()` and `Harbor.clearAllCache()` (#39, #52)
- SSL pinning with multiple keys for rotation: `Harbor.setSSlPinningKeys([String]?)` (#42)
- mTLS identity extraction via `HMTLSIdentity` (#45)
- Configurable timeout: `Harbor.setDefaultTimeoutInterval()` (default 15s) (#54)
- `Harbor.setLoggingEnabled()` (#50)
- New error cases `certificate` and `noCachedDataFound`, plus `HRequestError.mapURLError(_:)` (#53)
- Default implementations for request protocol properties (`needsAuth`, `retries`, `pathParameters`, `headerParameters`, `queryParameters`, `bodyType`) (#38)
- Claude AI skill documentation (#51)

### Changed
- Network monitoring migrated from SystemConfiguration to NWPathMonitor (#49)
- SHA256 migrated from CommonCrypto to CryptoKit (#47)
- Cache cleanup now runs in background (#48)
- Logging disabled by default in Release builds (#50)
- `requestStream` throws if the remote request fails even when cache is available (#46)
- Documentation updates (#37, #41)

### Fixed
- URL injection vulnerability: path and query parameters are now percent-encoded (#46)
- `clearCache` uses the proper URLRequest for URLCache (#52)
- 304 Not Modified handling (#52)
- SSL pinning exact hash comparison and trust evaluation logging (#42, #45)
- False `.noConnection` on the first request in Release (#55)

### ⚠️ Breaking Changes
- `Harbor.setSSlPinningSHA256(String?)` → `Harbor.setSSlPinningKeys([String]?)` (#42)
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
