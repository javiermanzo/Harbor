---
name: harbor-image
description: Use when writing, reviewing or debugging Swift code that loads, caches, processes or shows remote images with Harbor (import HarborImage) - HImageView, HImageRequestProtocol / HImageRequest, HarborImage.image(for:onEvent:), data(for:onEvent:), events(for:), HImageResult, HImageError, processors (resize, crop, mask, border, rotate, blur, tint, overlay, custom HImageProcessor), HImageEncoding (JPEG/PNG/HEIC compression), HImageCache / HImageCacheType / HImageCachePolicy, HImagePrefetcher, animated GIF/APNG/WebP, SVG, HImageDecoder, HImageMock. For auth, pinning, mTLS, retry policy and logging see harbor-core.
---

# HarborImage

`HarborImage` loads images through Harbor's pipeline (connectivity check, auth provider with the `401` refresh flow, default headers, retry policy, SSL pinning, mTLS, redirect policy, custom session), decodes them (JPEG, PNG, GIF, WebP, HEIC, AVIF, SVG, animated GIF/APNG/WebP), runs processors, caches them in memory and on disk, and shows them with `HImageView`. `import HarborImage` also brings the shared configuration (`harbor-core` skill); it doesn't need the REST product.

## Core rules

1. **Requests are structs.** Conform to `HImageRequestProtocol` (only `url` is required) or use `HImageRequest(url:...)`. URLs may be `http(s)`, `data:` or `file:`.
2. **Loads never throw.** `image(for:)` returns `HImageResponse` (`.success(HImageResult)` / `.failure(HImageError)`), `data(for:)` returns `HImageDataResponse`. Only `process`, `encode` and processors throw.
3. **Direct calls are `async`; callbacks are optional.** `image(for:onEvent:)` and `data(for:onEvent:)` take an optional `onEvent` that runs on the main actor; `events(for:)` gives the same events as an `AsyncStream`. There is no completion-handler variant: from code without an async context, open a `Task` (cancelling it cancels the load).
4. **Cancellation is per caller.** Concurrent loads of the same URL share one download (image and byte loads alike, the first caller's headers, auth and retry policy are used); a cancelled caller gets `.cancelled` at once, and the download stops only when no caller is left.
5. **Cache keys are URL + processing.** Never a header or credential: call `HarborImage.clearCache()` when the account changes, and use `.memoryOnly` / `.disabled` for private images.

```swift
import HarborImage

struct AvatarRequest: HImageRequestProtocol {
    let url = "https://api.example.com/users/{id}/avatar"
    let pathParameters: [String: String]?
    let needsAuth = true
    var processors: [any HImageProcessor] { [.resize(to: CGSize(width: 240, height: 240), mode: .fill), .mask(.circle)] }

    init(userId: Int) { pathParameters = ["id": String(userId)] }
}

// SwiftUI
HImageView(request: AvatarRequest(userId: 7)) { image in
    image.resizable().scaledToFit()
} placeholder: {
    ProgressView()
}
.transition(.fade())

// Without a view
let response = await HarborImage.image(for: AvatarRequest(userId: 7), onEvent: { event in
    if case .progress(let fraction) = event { print(fraction) }
})
```

## Gotchas

- Processors are part of the cache key through their `identifier`: a custom processor must return a stable identifier that includes every parameter.
- Processors receive pixel sizes, not points. Use `.downsampling(to:)` on `HImageView` (points × display scale) or `targetSize` on the request so large photos are decoded small; a first `.resize` processor downsamples while decoding too when the request has no `targetSize`.
- `HImageView` modifiers (`.processors`, `.transition`, `.onSuccess`, ...) must come before generic SwiftUI modifiers: they are defined on `HImageView` only.
- A transition does not run when the image comes from memory in the first render (no fade on every scroll).
- WebP is decoded but cannot be encoded (ImageIO has no encoder); HEIC encoding depends on the device and fails with `.encodingFailed` where unavailable.
- SVG supports a documented subset; outside it the load fails with `.unsupportedFormat` instead of rendering wrong (`svg.md`). Set `targetSize` / `.downsampling` to render it sharp at the displayed size.
- `HImageMock` is served in debug builds only, before the disk cache and the connectivity check, and is never written to disk; `URLProtocol` stubs need `Harbor.setProtocolClasses(_:)` from a test target.
- `HarborImage.store(_:for:)` and `remove(_:)` drop every cached copy of the image (all sizes and processings, memory and disk); a download in flight does not store over them.

## Where to look

| Need | Read |
|---|---|
| Every public type and function, by role | `reference.md` |
| Requests, direct calls and callbacks, `HImageView`, animated images, prefetching, mocks, testing | `examples.md` |
| Built-in processors, custom processors, compression and format conversion | `processing.md` |
| Memory and disk cache, keys, cache types and policies, offline, signed URLs | `cache.md` |
| What SVG supports and rejects | `svg.md` |
| Auth provider and `401` refresh, pinning, mTLS, custom `URLSession`, `HRetryPolicy`, logging | `../harbor-core/SKILL.md` |
