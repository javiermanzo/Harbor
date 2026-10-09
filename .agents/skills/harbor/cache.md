# Harbor Cache

Harbor caches GET requests (`HGetRequestProtocol`) only. The cache type is chosen per request (`cacheType`) or globally (`Harbor.setDefaultCacheType(_:)`).

## Cache types

```swift
func cacheTypes() async {
    // Default: URLCache with the protocol cache policy (URLSession handles HTTP caching)
    await Harbor.setDefaultCacheType(.urlCache())
    await Harbor.setDefaultCacheType(.urlCache(urlCache: URLCache(memoryCapacity: 10_000_000, diskCapacity: 50_000_000),
                                               requestCachePolicy: .returnCacheDataElseLoad))

    // Harbor's own memory (L1) + disk (L2) cache
    await Harbor.setDefaultCacheType(.custom(HCache.Configuration(
        expirationTime: .oneHour,        // fallback lifetime when the response has no explicit one; default .oneWeek
        maxObjectSizeInMBs: 10,          // larger bodies are not stored; default 10
        memoryCacheCapacityInMBs: 100,   // default 100
        diskCacheCapacityInMBs: 500      // default 100; LRU eviction when exceeded
    )))

    // No caching
    await Harbor.setDefaultCacheType(.disabled)
}
```

Values below 1 MB are clamped to 1. `expirationTime: .noExpiration` (`nil`) means no fallback lifetime. The `TimeInterval` helpers are `.oneMinute`, `.fiveMinutes`, `.fifteenMinutes`, `.thirtyMinutes`, `.oneHour`, `.sixHours`, `.twelveHours`, `.oneDay`, `.threeDays`, `.oneWeek`, `.oneMonth`, `.threeMonths`, `.sixMonths` and `.oneYear`.

Per request:

```swift
struct CatalogRequest: HGetRequestProtocol {
    typealias Model = [String]
    let url = "https://api.example.com/catalog"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneDay))
}

struct LivePriceRequest: HGetRequestProtocol {
    typealias Model = Double
    let url = "https://api.example.com/price"
    let cacheType: HCache.CacheType? = .disabled
}
```

A request's own `cacheType` wins over the global default. The memory limit of the custom cache follows the global `.custom` configuration, and a per-request configuration can only raise it.

## How `request()` uses the cache

- **`.urlCache`**: `URLSession` applies HTTP caching itself, according to `requestCachePolicy`.
- **`.custom`**: `request()` always contacts the server, so the custom cache is not a "cache-first" shortcut. Harbor uses it as follows:
  - **Conditional revalidation.** Stored `ETag` / `Last-Modified` values are sent as `If-None-Match` / `If-Modified-Since`, unless the request already sets either header (a caller-set validator is kept as-is). A `304` serves the cached body and refreshes the entry's lifetime and validators. If the `304` arrives but no cached body can be served (evicted, undecodable for this request, or another `Vary` variant), Harbor re-sends the request once without validators and uses that response. This only happens when Harbor injected the validators: a `304` answering caller-set validators is returned as `.api(statusCode: 304, data:)`.
  - **Store.** Every 2xx response is stored according to its directives. A `needsAuth` response is stored only under the credential it was actually sent with (the provider is not asked again when storing); a `needsAuth` request sent without a credential (the provider returned `nil`) is neither stored nor served from cache. A response whose request started before `Harbor.clearAllCache()` or `Harbor.setAuthProvider(_:)` is returned to its caller but neither stored nor remembered for offline lookups.
  - **Offline.** When the connectivity monitor reports `.unsatisfied`, or the request fails with no connection, Harbor serves a fresh entry or a `stale-if-error` entry. For `needsAuth` requests it remembers the credential used by the last successful online request for that URL and looks that entry up without calling the auth provider; when nothing is remembered the provider is asked for its current header, and the entry stored without credentials is never served in its place. The remembered credentials are forgotten when the auth provider is replaced and when `Harbor.clearAllCache()` runs. With `.urlCache` it serves the stored 2xx response unless the policy ignores local data. With nothing to serve, the error is `.noConnection`.
  - **Errors.** After retries are exhausted, a 5xx or a network error serves an expired entry that is still within its `stale-if-error` window.
- For cache-first UX, read the cache explicitly (`cache()`) or use `requestStream(source: .cacheAndRemote)`.

## HTTP semantics (custom cache)

- Lifetime: `max-age` > `Expires` (measured from the response `Date`) > `HCache.Configuration.expirationTime`. The response `Age` header is subtracted.
- `no-store`: not stored, and any previous entry for the key is evicted. Bodies larger than `maxObjectSizeInMBs` are treated the same way.
- `no-cache`: stored but always stale. It is never served without revalidation, and its validators are kept.
- `must-revalidate`: never served stale.
- `s-maxage` and `proxy-revalidate` are ignored: they only apply to shared caches, and Harbor's cache (like `URLCache`) is a private cache.
- `stale-while-revalidate`: `cache()` and `.cacheAndRemote` may serve the entry within that window after expiry.
- `stale-if-error`: served after network errors or 5xx responses within that window.
- `Vary`: the varying request header values are stored as a SHA-256 digest (never in clear) and enforced on reads. `Vary: *` entries are never served directly.
- Expired entries without validators are evicted once their `stale-if-error` window (if any) has elapsed; until then they are kept (by reads and by the startup cleanup) so they can still be served after errors. Expired entries with validators are kept as a source of `If-None-Match` / `If-Modified-Since`.

For `.urlCache`, `cache()` (and the cached leg of `requestStream(source: .cacheAndRemote)`) serves the stored 2xx response unless it is explicitly stale: `Cache-Control: no-cache` or `no-store`, an elapsed `max-age` / `Expires` lifetime (age from `Date` + `Age`, extended by `stale-while-revalidate`), or an elapsed 10% `Last-Modified` heuristic when a `Date` header is present. A response without freshness headers is served. A policy that explicitly prefers cached data (`.returnCacheDataElseLoad`, `.returnCacheDataDontLoad`) skips the check altogether.

## Cache keys and credentials

- The key is the composite URL (path parameters substituted, query items sorted by name and strictly percent-encoded).
- For `needsAuth` requests, `#harbor-auth=<sha256(header key:value)>` is appended. Each credential gets its own entries, and the raw token is never stored in the key.
- Replacing the auth provider or the token does **not** delete old entries. **Call `await Harbor.clearAllCache()` on logout.**

## Storage

- L1: `NSCache` bounded by body bytes.
- L2: `Library/Caches/HarborCache/`. Each entry is one file named `sha256(key).cache`, holding a length-prefixed JSON metadata header followed by the raw body (format version 2). Files in an older format, or from legacy versions, are deleted. Reads refresh the access time, and eviction is least-recently-used once `diskCacheCapacityInMBs` is exceeded. A background task at startup removes expired (outside any `stale-if-error` window) and outdated files.
- Cached bodies are decoded with the request's `parseData(data:model:)`, the same decoder as the network path. A body that does not decode for a request is a miss for that request but is kept, since request types with different models or parsers may share a URL. The next full response replaces it. On-disk access-time updates are throttled per entry (once per 60 s).

## API

```swift
struct ProfileRequest: HGetRequestProtocol {
    typealias Model = String
    let url = "https://api.example.com/profile"
    let needsAuth = true
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .fifteenMinutes))
}

func cacheAPI() async {
    // Cached model, or nil (miss, stale, Vary mismatch, other credential)
    let cached: String? = await ProfileRequest().cache()

    // Stored ETag (custom cache and URLCache)
    let etag: String? = await ProfileRequest().cachedETag()

    // Remove this request's entry (current credential + the credential-less entry)
    await ProfileRequest().clearCache()

    // Custom cache (memory + disk), URLCache.shared, and the URLCache of the default
    // cache type / custom session when they differ
    await Harbor.clearAllCache()
    _ = (cached, etag)
}
```

Only `cache()`, `cachedETag()` and `clearCache()` are public. For `needsAuth` requests they resolve the credential from the auth provider's current header.

## Streaming with cache

```swift
struct FeedRequest: HGetRequestProtocol {
    typealias Model = [String]
    let url = "https://api.example.com/feed"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .fiveMinutes))
}

func loadFeed() async {
    do {
        for try await (items, origin) in FeedRequest().requestStream(source: .cacheAndRemote) {
            print(origin == .cache ? "cached" : "fresh", items.count)
        }
    } catch {
        // .cacheAndRemote: thrown when the remote request fails, even after a cached element
        // .cacheOnly: HRequestError.noCachedDataFound on a miss
        print(error)
    }
}
```

The stream yields at most one `.cache` element (only when `cache()` returns a value) and one `.remote` element. It is not a chunked download.

## Best practices

- Use `.custom` for data you want offline, with ETags. Use `.disabled` for real-time or one-shot sensitive responses. Servers should send `Cache-Control: no-store` for secrets.
- Clear the cache on logout (`Harbor.clearAllCache()`).
- After a model change, old entries are misses and get replaced by the next network response. No migration is needed.

## Related files

- `Sources/Harbor/Cache/HCache+Manager.swift`: storage, directives, keys, disk codec.
- `Sources/Harbor/Cache/HGetRequestProtocol+Cache.swift`: `cache()`, `cachedETag()`, `clearCache()`, offline lookup.
- `Sources/Harbor/Cache/HCacheType.swift`, `HCacheConfiguration.swift`, `TimeInterval+Cache.swift`.
