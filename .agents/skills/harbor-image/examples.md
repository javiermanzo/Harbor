# HarborImage examples

## Request requirements

| Requirement | Default | Notes |
|---|---|---|
| `url` | required | `http`, `https`, `data:` or `file:`; `{name}` placeholders for path parameters |
| `pathParameters`, `queryParameters`, `headerParameters` | `nil` | Same encoding as REST requests |
| `needsAuth` | `false` | The auth provider's header, with the `401` refresh flow |
| `retryPolicy` | `nil` | Falls back to `HarborImage.setDefaultRetryPolicy(_:)` |
| `timeoutInterval` | `nil` | Harbor's default timeout |
| `cacheType` | `nil` | Falls back to `HarborImage.setDefaultCacheType(_:)` (`.memoryAndDisk`) |
| `cachePolicy` | `.useCache` | `.reloadIgnoringCache`, `.returnCacheDontLoad` |
| `cacheKey`, `ignoredQueryParameters` | `nil`, `[]` | For signed URLs (`cache.md`) |
| `processors` | `[]` | `processing.md` |
| `encoding` | `nil` | `processing.md` |
| `targetSize` | `nil` | Decoding size in pixels (downsampling) |
| `fallbackURLs` | `[]` | Tried when the main URL fails (after its retries) with an HTTP, transport, timeout, size or decoding error; cached under the main URL |

## Direct calls

```swift
// async, no callback
let response = await HarborImage.image(for: HImageRequest(url: url))
switch response {
case .success(let result):
    print(result.image.width, result.format, result.source)   // .memory, .disk, .network, .local
case .failure(let error):
    print(error.localizedDescription)
}

// async with an optional callback (main actor); every event is delivered before it returns
let response = await HarborImage.image(for: request, onEvent: { event in
    switch event {
    case .started: break
    case .progress(let fraction): progress = fraction       // only with Content-Length
    case .retrying(let attempt): print("retry", attempt)
    case .loaded(let source): print(source)
    case .finished: break
    }
})

// From code without an async context (a UIKit cell): a Task
let task = Task {
    let response = await HarborImage.image(for: request)
    cell.imageView.image = response.result.map { UIImage(cgImage: $0.image) }
}
task.cancel()   // the load returns .failure(.cancelled); no event is delivered after it

// An AsyncStream instead of a callback
for await event in HarborImage.events(for: request) { ... }

// Original bytes (to save or share), not decoded nor processed
let data = await HarborImage.data(for: request).data
```

## HImageView

```swift
HImageView(url: url)                                     // image at its size, gray placeholder

HImageView(url: url) { image in
    image.resizable().scaledToFill()
} placeholder: {
    Color.gray.opacity(0.2)
}

HImageView(request: request) { phase in
    switch phase {
    case .empty(let progress): ProgressView(value: progress ?? 0)
    case .success(let image): image.resizable().scaledToFit()
    case .failure(let error): Label(error.localizedDescription, systemImage: "photo")
    }
}
.processors([.resize(to: CGSize(width: 300, height: 300), mode: .fill), .roundedCorners(24)])
.encoding(.jpeg(quality: 0.8))
.downsampling(to: CGSize(width: 100, height: 100))       // points; pixels use the display scale
.cacheType(.memoryOnly)
.cachePolicy(.reloadIgnoringCache)
.retryPolicy(HRetryPolicy(maxRetries: 2))
.transition(.fade())                                     // .none, .fade, .scale, .blur, .custom
.transition(.custom(.move(edge: .bottom).combined(with: .opacity), animation: .spring))
.animatedPlayback(HAnimatedImagePlayback(loopCount: 1, speed: 2))   // or .disabled
.imageScale(2)
.imageAccessibilityLabel(Text("Profile photo"))          // decorative without one
.onSuccess { result in }                                 // optional, main actor
.onFailure { error in }
.onProgress { fraction in }
```

- The load runs in `.task(id:)`: leaving the screen cancels it and stops an animated image, which starts over from the first frame when the view comes back. Changing the URL, processors, encoding, downsampling or cache policy reloads; `.cacheType`, `.retryPolicy`, headers and `needsAuth` do not restart a view on screen.
- When the request changes (a reused row), the view shows the new image from memory, or its placeholder, never the previous request's image or error.
- An image in memory is shown in the first render, without the placeholder or the transition.

## Animated images

GIF, APNG and animated WebP play in `HImageView` (frames decoded on demand, a few kept in memory). To draw them yourself, disable playback and read the frames:

```swift
let result = await HarborImage.image(for: request).result
if let animation = result?.animation {
    for index in 0..<animation.frameCount {
        let frame = await animation.frame(at: index)        // processed like the first frame
        try await Task.sleep(nanoseconds: UInt64(animation.frameDurations[index] * 1_000_000_000))
    }
}
```

`loopCount` is `0` for forever (a GIF without a loop count plays once). Animated images keep their original bytes on disk, also with processors or an `encoding` (a still variant would lose the animation), and are processed again when read. Only GIF, APNG and WebP animate: an ICO with several sizes or a multi-page TIFF shows its largest image.

## Prefetching

```swift
let prefetcher = HImagePrefetcher(maxConcurrent: 3)                  // .disk by default
let report = await prefetcher.prefetch(nextPage.map { HImageRequest(url: $0) })
print(report.completed, report.failed, report.cancelled)

await prefetcher.start(requests)     // without waiting
await prefetcher.cancel()            // stops what start(_:) launched, not the loads of visible views

HImagePrefetcher(destination: .memoryAndDisk)                          // decoded, ready for the first render

List { ... }
    .hImagePrefetch(upcoming)  // while the view is on screen
```

A `.memoryAndDisk` prefetch only warms the first render when its requests have the same processors, encoding and `targetSize` as the view: the memory key includes them. A `.disk` prefetch warms every processing of the image, and a view that appears while it runs shares its download.

## Custom decoders

```swift
struct JXLDecoder: HImageDecoder {
    let format = HImageFormat(rawValue: "jxl")
    func canDecode(_ data: Data) -> Bool { data.starts(with: [0xFF, 0x0A]) }
    func decode(_ data: Data, targetSize: HImageTargetSize?) throws -> CGImage { ... }
}

await HarborImage.registerDecoder(JXLDecoder())   // asked before the built-in decoders
```

## Limits

- `HarborImage.setMaxDownloadSizeInMBs(_:)` (30 MB): checked against `Content-Length` and while the body of a successful response arrives → `.tooLarge`. The body of an error status is discarded, so a `401` or `503` still goes through the refresh or the retry. `data:` and `file:` URLs and mocks are not bounded.
- `HarborImage.setMaxImagePixels(_:)` (100 MP): checked before decoding (before rasterizing an SVG; after decoding for a custom `HImageDecoder`) → `.tooManyPixels`.
- `HarborImage.setMaxConcurrentDownloads(_:)` (6): a change applies at once, also to queued downloads.
- The format is detected from the bytes: an HTML page served with `200` is `.notAnImage`.

## Errors

`HImageError`: `.invalidURL`, `.noConnection`, `.authProviderNeeded`, `.authNeeded`, `.api(statusCode:)`, `.timeout`, `.certificate`, `.network(URLError)`, `.notCached`, `.cancelled`, `.tooLarge`, `.tooManyPixels`, `.notAnImage`, `.unsupportedFormat`, `.decodingFailed`, `.processingFailed`, `.encodingFailed`. It conforms to `LocalizedError` and `Equatable`.

## Mocks and testing

```swift
await HarborImage.register(HImageMock(url: "https://cdn.example.com/a.png", data: previewPNG))
await HarborImage.register(HImageMock(url: "https://cdn.example.com/b.png", error: .api(statusCode: 404), delay: 1))
await HarborImage.removeAllMocks()
```

Mocks are served in debug builds only, before the disk cache and the connectivity check (they answer offline too), report `.local` and are never written to disk. Tests in this repository stub the transport with `ImageStubProtocol` installed through `Harbor.setProtocolClasses(_:)` (see `Tests/HarborImageTests/Helpers`), generate their images in code, and reset the configuration with `ImageTestDefaults.restore()` / `tearDown()`.
