# Changelog

## [Unreleased]

### Added
- Complete caching system with `HCacheManager` and configurable expiration
- `HURLBuilder` utility for centralized URL construction
- Cache configuration APIs and TimeInterval extensions
- Comprehensive test suites for cache and debug functionality

### Fixed
- Updated `SecTrustEvaluate` to `SecTrustEvaluateWithError` (iOS 13+ compatibility)
- Improved SSL pinning security with exact hash comparison
- Enhanced error logging for SSL trust evaluation and pinning failures
