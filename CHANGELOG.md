# Changelog

## 3.1.0 - Complete caching system and URL utilities (2025-XX-XX)

### Added
- Complete caching system with `HCacheManager` (L1 memory + L2 disk cache)
- `HCache.CacheType` enum with `.urlCache`, `.custom`, and `.disabled` options
- **URLCache is now the default** - automatic ETag/304 support
- Custom cache with manual TTL and size control
- `HURLBuilder` utility for centralized URL construction
- `AsyncThrowingStream` via `requestStream()` for cache+remote data
- `HRequestSource` enum (`remoteOnly`, `cacheOnly`, `cacheAndRemote`)
- `HOriginType` enum (`cache`, `remote`) to identify data source
- Multiple SSL pinning keys support for key rotation
- `Harbor.setDefaultCacheType()`, `Harbor.setLoggingEnabled()`, `Harbor.clearAllCache()`

### Changed
- `Harbor.setSSlPinningSHA256(_:)` renamed to `Harbor.setSSlPinningKeys(_:)` - now accepts array for key rotation
- Network monitoring migrated from SystemConfiguration to NWPathMonitor
- SHA256 migrated from CommonCrypto to CryptoKit
- Renamed error cases for consistency: `apiError` → `api`, `codableError` → `codable`, `noConnectionError` → `noConnection`, `malformedRequestError` → `malformedRequest`, `timeoutError` → `timeout`, `sslError` → `certificate`
- Added `HRequestError.mapURLError(_:)` static method for URL error mapping

### Fixed
- clearCache now uses proper URLRequest for URLCache
- 304 Not Modified cache handling
- SSL pinning security with exact hash comparison
- SSL trust evaluation error logging
- RequestStream throws error if remote fails even with cache available

### ⚠️ Breaking Changes
- SSL pinning: `setSSlPinningSHA256(String?)` → `setSSlPinningKeys([String]?)`
- Error cases renamed: `apiError` → `api`, `codableError` → `codable`, `noConnectionError` → `noConnection`, `malformedRequestError` → `malformedRequest`, `timeoutError` → `timeout`, `sslError` → `certificate`

## 3.0.0 - Response cases, Logging (2023-12-25)

### Changed
- Moved canceled response case to an error case

### Added
- Implemented LogBird for logging

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
