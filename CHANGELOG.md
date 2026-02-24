# Changelog

## 3.1.0 - Complete caching system and URL utilities

### Added
- Complete caching system with `HCacheManager`
- `HURLBuilder` utility for centralized URL construction  
- `AsyncThrowingStream` support with `requestStream()` for cache+remote data
- `HCache.Policy` enum with `.urlCache`, `.custom`, and `.disabled` options
- **URLCache is now the default** - provides automatic ETag/304 support via Apple's URLCache
- Custom cache continues to provide manual TTL and size control
- `clearCache()` support for both URLCache and custom cache policies
- Comprehensive test suites

### Fixed
- Updated `SecTrustEvaluate` to `SecTrustEvaluateWithError` (iOS 13+ compatibility)
- Improved SSL pinning security with exact hash comparison
- Enhanced error logging for SSL trust evaluation and pinning failures

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
