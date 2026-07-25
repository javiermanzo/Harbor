# Harbor Cache System

Complete guide to Harbor's two-level caching system for optimizing network requests.

## Overview

Harbor implements a sophisticated two-level cache system:

1. **Level 1 (Memory)**: NSCache for fast in-memory access
2. **Level 2 (Disk)**: FileSystem cache for persistent storage

**Performance**: Cache hits are approximately **2.5-2.9x faster** than network requests.

**Location**: `Sources/Harbor/Cache/`

## Architecture

### Two-Level Cache Flow

```
Request
    │
    ▼
Memory Cache (L1)
    │
    ├─ Hit → Return cached data immediately
    │
    └─ Miss
        │
        ▼
    Disk Cache (L2)
        │
        ├─ Hit → Load to memory → Return data
        │
        └─ Miss
            │
            ▼
        Network Request
            │
            ├─ Success → Store in L2 → Store in L1 → Return data
            │
            └─ Error → Return error
```

### Cache Manager

**Location**: `Sources/Harbor/Cache/HCacheManager.swift`

```swift
@HRequestManagerActor
final class Manager {
    static let shared = Manager()
    
    private let memoryCache = NSCache<NSString, CacheEntry>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
}
```

**Key Features:**
- Actor-isolated for thread safety
- Automatic cleanup of expired entries
- Respects HTTP cache headers
- Configurable size limits

## Configuration

### Cache Configuration Types

**Location**: `Sources/Harbor/Cache/HCachePolicy.swift`

```swift
enum CacheType {
    case urlCache(urlCache: URLCache, requestCachePolicy: NSURLRequest.CachePolicy)
    case custom(Configuration)
    case disabled
}
```

**Location**: `Sources/Harbor/Cache/HCacheConfiguration.swift`

```swift
struct Configuration: Sendable, Equatable {
    let expirationTime: TimeInterval?
    let maxObjectSizeInMBs: Int
    let memoryCacheCapacityInMBs: Int
}
```

**Options:**

1. **Disabled** - No caching
```swift
let cacheType: HCache.CacheType? = .disabled
// or simply
let cacheType: HCache.CacheType? = nil
```

2. **Enabled** - Cache with expiration time
```swift
let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneHour))
```

3. **Custom** - Cache with expiration and size limit
```swift
let cacheType: HCache.CacheType? = .custom(HCache.Configuration(
    expirationTime: .oneDay,
    maxObjectSizeInMBs: 5  // 5MB max per object
))
```

### Predefined Expiration Times

**Location**: `Sources/Harbor/Cache/TimeInterval+Cache.swift`

```swift
extension TimeInterval {
    static var oneMinute: TimeInterval { 60 }
    static var fiveMinutes: TimeInterval { 300 }
    static var fifteenMinutes: TimeInterval { 900 }
    static var thirtyMinutes: TimeInterval { 1800 }
    static var oneHour: TimeInterval { 3600 }
    static var sixHours: TimeInterval { 21600 }
    static var twelveHours: TimeInterval { 43200 }
    static var oneDay: TimeInterval { 86400 }
    static var threeDays: TimeInterval { 259200 }
    static var oneWeek: TimeInterval { 604800 }
    static var oneMonth: TimeInterval { 2592000 }   // 30 days
    static var threeMonths: TimeInterval { 7776000 } // 90 days
    static var sixMonths: TimeInterval { 15552000 }  // 180 days
    static var oneYear: TimeInterval { 31536000 }    // 365 days
}
```

**Usage:**
```swift
.custom(HCache.Configuration(expirationTime: .oneMinute))
.custom(HCache.Configuration(expirationTime: .fiveMinutes))
.custom(HCache.Configuration(expirationTime: .fifteenMinutes))
.custom(HCache.Configuration(expirationTime: .thirtyMinutes))
.custom(HCache.Configuration(expirationTime: .oneHour))
.custom(HCache.Configuration(expirationTime: .sixHours))
.custom(HCache.Configuration(expirationTime: .twelveHours))
.custom(HCache.Configuration(expirationTime: .oneDay))
.custom(HCache.Configuration(expirationTime: .threeDays))
.custom(HCache.Configuration(expirationTime: .oneWeek))
.custom(HCache.Configuration(expirationTime: .oneMonth))
.custom(HCache.Configuration(expirationTime: .threeMonths))
.custom(HCache.Configuration(expirationTime: .sixMonths))
.custom(HCache.Configuration(expirationTime: .oneYear))
```

## Global vs Per-Request Configuration

### Global Configuration

Set default cache behavior for all requests:

```swift
// Enable cache globally with 1 hour expiration
await Harbor.setDefaultCacheType(.custom(HCache.Configuration(expirationTime: .oneHour)))

// All requests without explicit cache config will use this
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/user"
    // Will use global cache configuration
}
```

### Per-Request Configuration

Override global settings for specific requests:

```swift
// Request-specific cache configuration
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/user"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneDay))
    // This overrides global configuration
}

// Disable cache for specific request
struct GetBalanceRequest: HGetRequestProtocol {
    typealias Model = Balance
    let url = "https://api.example.com/balance"
    let cacheType: HCache.CacheType? = .disabled
    // Never cache this request
}
```

### Priority Order

1. **Per-request configuration** takes precedence
2. **Global configuration** is used if per-request is not set
3. **No caching** if neither is configured

## Cache Usage Patterns

### Static Data (Long Cache)

```swift
// Country list - rarely changes
struct GetCountriesRequest: HGetRequestProtocol {
    typealias Model = [Country]
    let url = "https://api.example.com/countries"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneWeek))
}
```

### Semi-Static Data (Medium Cache)

```swift
// User profile - changes occasionally
struct GetUserProfileRequest: HGetRequestProtocol {
    typealias Model = UserProfile
    let url = "https://api.example.com/profile"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneHour))
}
```

### Dynamic Data (Short Cache)

```swift
// News feed - updates frequently
struct GetFeedRequest: HGetRequestProtocol {
    typealias Model = [Post]
    let url = "https://api.example.com/feed"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .fiveMinutes))
}
```

### Real-Time Data (No Cache)

```swift
// Balance - must be current
struct GetBalanceRequest: HGetRequestProtocol {
    typealias Model = Balance
    let url = "https://api.example.com/balance"
    let cacheType: HCache.CacheType? = .disabled
}
```

## HTTP Header Compliance

Harbor respects standard HTTP cache headers:

### Cache-Control Header

```
Cache-Control: max-age=3600
```

Harbor will use the smaller of:
- Configured expiration time
- HTTP `max-age` value

**Example:**
```swift
// Request configured for 1 day cache
let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneDay))

// But server responds with: Cache-Control: max-age=3600 (1 hour)
// Harbor will cache for 1 hour (respects server preference)
```

### Expires Header

```
Expires: Wed, 21 Oct 2026 07:28:00 GMT
```

Harbor checks the `Expires` header if `Cache-Control` is not present.

### No-Cache Directives

```
Cache-Control: no-cache
Cache-Control: no-store
```

These directives prevent caching regardless of request configuration.

## Cache Size Limits

### Default Limits

**Memory Cache (L1):**
- Managed by NSCache
- Automatically evicts under memory pressure
- No explicit size limit (iOS manages it)

**Disk Cache (L2):**
- Default max object size: 10MB
- Can be customized per request

### Custom Size Limits

```swift
// Limit cache objects to 5MB
let cacheType: HCache.CacheType? = .custom(HCache.Configuration(
    expirationTime: .oneHour,
    maxObjectSizeInMBs: 5
))

// Larger images might need bigger limits
let cacheType: HCache.CacheType? = .custom(HCache.Configuration(
    expirationTime: .oneDay,
    maxObjectSizeInMBs: 20  // 20MB
))
```

**Objects exceeding the limit are not cached.**

## Cache Management APIs

### Direct Cache Access

```swift
// Get cached data for a request
let request = GetUserRequest(userId: "123")
if let cachedUser = await request.cache() {
    print("Found cached user: \(cachedUser)")
}
```

### Clear Specific Cache

```swift
// Clear cache for a specific request
let request = GetUserRequest(userId: "123")
await request.clearCache()
```

### Clear All Cache

```swift
// Clear all cached data
await Harbor.clearAllCache()
```

**Use Cases:**
- User logout (clear all cached data)
- Force refresh (clear specific cache)
- Manual cache management in settings

### Example: Refresh Pattern

```swift
// Force refresh by clearing cache first
await request.clearCache()
let response = await request.request()  // Always hits network
```

## Streaming with Cache

Harbor supports streaming data from cache and network sources.

### Request Source Types

**Location**: `Sources/Harbor/Request/HRequestProtocol.swift`

```swift
enum HRequestSource {
    case cacheOnly      // Only return cached data
    case remoteOnly     // Only fetch from network
    case cacheAndRemote // Return cache first, then network
}
```

### Data Origin

```swift
enum HOriginType {
    case cache   // Data came from cache
    case remote  // Data came from network
}
```

### Streaming API

```swift
func requestStream(source: HRequestSource = .cacheAndRemote) 
    -> AsyncThrowingStream<(Model, HOriginType), Error>
```

### Example: Cache Then Network

```swift
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/user"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneHour))
}

// Stream will emit twice: first from cache, then from network
for try await (user, origin) in GetUserRequest().requestStream(source: .cacheAndRemote) {
    switch origin {
    case .cache:
        print("Showing cached user: \(user.name)")
        // Update UI with cached data (fast)
    case .remote:
        print("Showing fresh user: \(user.name)")
        // Update UI with fresh data
    }
}
```

### Example: Cache Only

```swift
// Only check cache, no network request
for try await (user, origin) in request.requestStream(source: .cacheOnly) {
    print("Cached user: \(user.name)")
}
// If no cache exists, stream completes without emitting
```

### Example: Remote Only

```swift
// Only fetch from network, ignore cache
for try await (user, origin) in request.requestStream(source: .remoteOnly) {
    print("Fresh user: \(user.name)")
}
// Cache is still updated for future requests
```

### SwiftUI Integration

```swift
struct UserView: View {
    @State private var user: User?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let user = user {
                UserDetailView(user: user)
            } else {
                ProgressView()
            }
        }
        .task {
            await loadUser()
        }
    }
    
    func loadUser() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            for try await (user, origin) in GetUserRequest().requestStream() {
                await MainActor.run {
                    self.user = user
                    if origin == .cache {
                        // Show refresh indicator
                    }
                }
            }
        } catch {
            print("Error: \(error)")
        }
    }
}
```

## Cache Key Generation

Harbor generates unique cache keys based on:

1. **URL**: Full request URL
2. **Query Parameters**: All query parameters
3. **HTTP Method**: GET, POST, etc.
4. **Headers**: Custom headers (if they affect response)

**Key Format:**
```
SHA256(url + queryParams + method + relevantHeaders)
```

**Example:**
```swift
// These generate different cache keys:
GetUserRequest(userId: "123")  // Key: hash of "/users/123"
GetUserRequest(userId: "456")  // Key: hash of "/users/456"

SearchRequest(query: "test", page: 1)  // Key: hash of "/search?query=test&page=1"
SearchRequest(query: "test", page: 2)  // Key: hash of "/search?query=test&page=2"
```

## Cache Expiration

### Expiration Check

Cache entries are checked for expiration on:
1. **Cache read**: Expired entries return as cache miss
2. **Periodic cleanup**: Background cleanup of expired entries

### Expiration Logic

```swift
let currentTime = Date()
let cacheAge = currentTime.timeIntervalSince(cacheEntry.timestamp)

if cacheAge > expirationTime {
    // Cache expired - remove entry
    // Fetch from network
} else {
    // Cache valid - return cached data
}
```

### HTTP Header Priority

```swift
// 1. Check Cache-Control max-age
if let maxAge = response.cacheControl?.maxAge {
    effectiveExpiration = min(configuredExpiration, maxAge)
}

// 2. Check Expires header
else if let expires = response.expires {
    effectiveExpiration = expires.timeIntervalSinceNow
}

// 3. Use configured expiration
else {
    effectiveExpiration = configuredExpiration
}
```

## Best Practices

### 1. Cache Static Data Aggressively

```swift
// Reference data - cache for a week
struct GetCategoriesRequest: HGetRequestProtocol {
    typealias Model = [Category]
    let url = "https://api.example.com/categories"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneWeek))
}
```

### 2. Don't Cache Sensitive Data

```swift
// User balance - always fresh
struct GetBalanceRequest: HGetRequestProtocol {
    typealias Model = Balance
    let url = "https://api.example.com/balance"
    let cacheType: HCache.CacheType? = .disabled
}
```

### 3. Use Streaming for Better UX

```swift
// Show cached data immediately, update with fresh data
for try await (posts, origin) in GetPostsRequest().requestStream() {
    updateUI(with: posts)
    if origin == .cache {
        showRefreshIndicator()
    } else {
        hideRefreshIndicator()
    }
}
```

### 4. Clear Cache on Logout

```swift
func logout() async {
    await Harbor.clearAllCache()
    // Clear auth tokens
    // Navigate to login
}
```

### 5. Cache Large Responses

```swift
// Large image data - cache with size limit
struct GetImageRequest: HGetRequestProtocol {
    typealias Model = Data
    let url: String
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(
        expirationTime: .oneWeek,
        maxObjectSizeInMBs: 10  // 10MB
    ))
}
```

### 6. Respect Server Cache Headers

Don't override server cache directives. If the server says `no-cache`, Harbor respects it automatically.

### 7. Use Appropriate Expiration Times

| Data Type | Recommended Expiration |
|-----------|------------------------|
| Static reference data | 1 week - 1 month |
| User profile | 1 hour - 1 day |
| Content lists | 5-15 minutes |
| Real-time data | No cache |
| Large media files | 1 week - 1 month |
| Session data | 30 minutes - 12 hours |

## Performance Considerations

### Memory Usage

**NSCache automatically manages memory:**
- Evicts objects under memory pressure
- No manual management needed
- Thread-safe by default

**To minimize memory:**
```swift
// Large objects should have size limits
let cacheType: HCache.CacheType? = .custom(HCache.Configuration(
    expirationTime: .oneDay,
    maxObjectSizeInMBs: 5  // Limit to 5MB
))
```

### Disk Usage

**Disk cache is persistent but limited:**
- Respects `maxObjectSizeInMBs` setting
- Expired entries cleaned up periodically
- Manual cleanup with `clearAllCache()`

**Monitor disk usage:**
```swift
// Implement periodic cleanup in app
Task {
    // Clean cache every 7 days
    if lastCleanup.timeIntervalSinceNow > .oneWeek {
        await Harbor.clearAllCache()
        lastCleanup = Date()
    }
}
```

### Network Efficiency

**Cache hits avoid network entirely:**
- 2.5-2.9x faster than network requests
- Reduces data usage
- Works offline

**Streaming provides best UX:**
- Instant display from cache
- Fresh data loaded in background
- Seamless updates

## Troubleshooting

### Cache Not Working

**Check configuration:**
```swift
// Ensure cache is enabled
let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneHour))

// Not disabled
// let cacheType: HCache.CacheType? = .disabled
```

**Check HTTP headers:**
```swift
// Server might send no-cache
// Cache-Control: no-cache
// This prevents caching regardless of configuration
```

### Cache Returning Stale Data

**Check expiration time:**
```swift
// Might be too long
.custom(HCache.Configuration(expirationTime: .oneWeek))

// Try shorter expiration
.custom(HCache.Configuration(expirationTime: .tenMinutes))
```

**Force refresh:**
```swift
await request.clearCache()
let response = await request.request()
```

### Cache Taking Too Much Space

**Set size limits:**
```swift
.custom(HCache.Configuration(
    expirationTime: .oneDay, maxObjectSizeInMBs: 2)
```

**Periodic cleanup:**
```swift
await Harbor.clearAllCache()
```

## Related Files

**Cache Implementation:**
- `Sources/Harbor/Cache/HCacheManager.swift` - Cache manager and storage
- `Sources/Harbor/Cache/HCachePolicy.swift` - Cache type definitions
- `Sources/Harbor/Cache/HCacheConfiguration.swift` - Cache configuration
- `Sources/Harbor/Cache/TimeInterval+Cache.swift` - Predefined expiration times
- `Sources/Harbor/Request/HRequestProtocol.swift` - Streaming APIs

**Examples:**
- `Example/HarborExample/Requests/RESTRequest.swift` - Cache usage example
- `Tests/HarborTests/HarborCacheTests.swift` - Cache tests
- `Tests/HarborTests/HarborStreamTests.swift` - Streaming tests
