# Image cache

## Layers

| Layer | Holds | Size | Read |
|---|---|---|---|
| Memory (`NSCache`) | Decoded images, by URL + processing + decoding size; entries do not expire | `memoryCacheCapacityInMBs` (100 MB) of decoded bytes (`bytesPerRow × height`, times the frames an animation keeps decoded); emptied on memory warnings (UIKit platforms) | Synchronously: `HImageView` shows a cached image in its first render |
| Disk (`Caches/HarborImage`) | Original bytes and processed variants, one file per key named by SHA-256 digests | `diskCacheCapacityInMBs` (300 MB), least recently used evicted past it (down to 90%); files above `maxObjectSizeInMBs` (20 MB) are not written | Off the main actor; the index is rebuilt from the file attributes on first use |

```swift
await HarborImage.setCacheConfiguration(HImageCache.Configuration(
    expirationTime: 7 * 24 * 60 * 60,    // nil never expires
    maxObjectSizeInMBs: 20,
    memoryCacheCapacityInMBs: 100,
    diskCacheCapacityInMBs: 300,
    storesOriginalWhenProcessed: false,
    directory: nil                        // Caches/HarborImage
))
```

## Cache types and policies

| `HImageCacheType` | Memory | Disk |
|---|---|---|
| `.memoryAndDisk` (default) | ✓ | ✓ |
| `.memoryOnly` | ✓ | — (private images that must not outlive the process) |
| `.diskOnly` | — | ✓ |
| `.disabled` | — | — |

| `HImageCachePolicy` | Behavior |
|---|---|
| `.useCache` (default) | Memory, then a disk entry that has not expired, then the network. When the download fails for a transient reason (transport error, timeout, `5xx`), an expired disk entry is served instead; a `4xx` is reported. |
| `.reloadIgnoringCache` | Network, then replaces the cached copy (pull-to-refresh). Offline it fails with `.noConnection`, even when the image is cached. |
| `.returnCacheDontLoad` | Memory or disk, even expired; never downloads (`.notCached`). |

- `Cache-Control: no-store` responses are not written to disk (they are still kept in memory).
- An expired disk entry is not deleted when it is read: it stays until a newer copy replaces it or the LRU evicts it.
- A processed variant expires with the original it was rendered from.

## Keys

- Original: the composed URL without its fragment (or `cacheKey`). `data:` URLs use a digest of their content.
- Variant: original + processor identifiers + encoding + decoding size (a variant is rendered from the downsampled image, so each size is its own variant). Its file name starts with the digest of the original, so every variant of an image can be found from the original key.
- Memory: the variant key, or the original key + decoding size when there is no processing.
- **No header ever reaches a key or a file**, so credentials are never stored, and entries are shared by every account: call `HarborImage.clearCache()` on logout or account switch.
- A load that started before `clearCache()`, `Harbor.setAuthProvider(_:)`, `store(_:for:)` or `remove(_:)` returns its image but does not store it, and a load that starts after them never joins it.

### Signed URLs

A signed URL changes its query on every request and would never hit the cache:

```swift
HImageRequest(url: "https://cdn.example.com/a.jpg",
              queryParameters: ["Expires": expires, "Signature": signature],
              ignoredQueryParameters: ["Expires", "Signature"])   // or cacheKey: "photo-42"
```

## Offline

When the connectivity monitor reports no network, an expired disk entry is served (with `.useCache`); without one the load fails with `.noConnection`. A registered mock answers before any of this, offline too.

## Managing the cache

```swift
let cached = await HarborImage.cached(for: request)       // memory or disk, no download
await HarborImage.store(uploadedData, for: request)       // e.g. right after an upload
await HarborImage.remove(request)
await HarborImage.clearCache()                            // .memory, .disk, .all
let bytes = await HarborImage.diskCacheSize()
let files = await HarborImage.diskCacheCount()
```

- `store(_:for:)` and `remove(_:)` drop every cached copy of the image first: all its sizes and processings, in memory and on disk. `store` writes the new bytes as the original and returns `false` when it stored nothing (not an image, an invalid URL, a `.memoryOnly` or `.disabled` request, or bytes above `maxObjectSizeInMBs`).
