# HarborImage API reference

Every public symbol of the module, grouped by role. The DocC comments in `Sources/HarborImage` are the authoritative description; this table is for finding the right symbol.

## Configuration (`HarborImage`, isolated to `@HRequestManagerActor`: call with `await` from outside)

| Function | Default | Purpose |
|---|---|---|
| `setCacheConfiguration(_:)` | `HImageCache.Configuration()` | Cache sizes, expiration, directory (`cache.md`) |
| `setDefaultCacheType(_:)` | `.memoryAndDisk` | Cache type of requests that set none |
| `setDefaultRetryPolicy(_:)` | `nil` | Retry policy of requests that set none |
| `setMaxDownloadSizeInMBs(_:)` | 30 | Larger downloads fail with `.tooLarge` |
| `setMaxImagePixels(_:)` | 100,000,000 | Larger images fail with `.tooManyPixels` before decoding (after, for a custom decoder) |
| `setMaxConcurrentDownloads(_:)` | 6 | Downloads running at once |
| `registerDecoder(_:)`, `removeAllDecoders()` | none | Custom `HImageDecoder`s, asked first |
| `setMocksEnabled(_:)`, `register(_:)`, `removeAllMocks()` | enabled, none | `HImageMock`s, debug builds only |

Network settings (auth, pinning, mTLS, timeouts, headers, logging) are the shared `Harbor.setX(_:)` of `harbor-core`.

## Loading (`HarborImage`)

| Function | Returns | Notes |
|---|---|---|
| `image(for:onEvent:)` | `HImageResponse` | `async`, never throws; optional `HImageEventHandler` on the main actor |
| `data(for:onEvent:)` | `HImageDataResponse` | Original bytes, checked to be an image, not decoded |
| `events(for:)` | `AsyncStream<HImageEvent>` | The events without a callback; cancelled with the iterating task |
| `prefetch(_:)` | `HImagePrefetchReport` | Default `HImagePrefetcher` (3 at once, to disk) |
| `cached(for:)`, `store(_:for:)`, `remove(_:)`, `clearCache(_:)`, `diskCacheSize()`, `diskCacheCount()` | | Cache management (`cache.md`) |
| `process(_:with:)` | `CGImage` (`throws(HImageError)`) | Processors on an image the app already has |
| `encode(_:as:)` | `Data` (`throws(HImageError)`) | Compression and format conversion |

## Requests and results

| Type | Role |
|---|---|
| `HImageRequestProtocol` | The request protocol; only `url` is required (`examples.md`, requirements table) |
| `HImageRequest` | Ready-made request struct with every requirement as an `init` parameter |
| `HImageTargetSize` (`ContentMode`: `.fit`, `.fill`) | Decoding size in pixels (`init(pixelWidth:pixelHeight:contentMode:)`, `init(size:scale:contentMode:)`) |
| `HImageResponse` | `.success(HImageResult)` / `.failure(HImageError)`; `result`, `error` accessors |
| `HImageDataResponse` | `.success(data:format:source:)` / `.failure`; `data`, `error` accessors |
| `HImageResult` | `init(image:data:format:source:animation:)`; `image`, `data`, `format` (of `data`), `source`, `animation`, `pixelSize` |
| `HImageSource` | `.memory`, `.disk`, `.network`, `.local` |
| `HImageFormat` | `.jpeg`, `.png`, `.gif`, `.webp`, `.heic`, `.avif`, `.tiff`, `.bmp`, `.ico`, `.svg`, or a custom `rawValue` |
| `HImageEvent` | `.started`, `.progress(Double)`, `.retrying(attempt:)`, `.loaded(source:)`, `.finished(HImageResponse)` |
| `HImageEventHandler` | `@Sendable @MainActor (HImageEvent) -> Void` |
| `HImageError` | Every failure (`examples.md`, Errors); `LocalizedError`, `Equatable` |
| `HImageAnimation` | `frameCount`, `frameDurations`, `loopCount`, `duration`, `frame(at:)` |
| `HImageDecoder` | Protocol for custom formats: `format`, `canDecode(_:)`, `decode(_:targetSize:)` |
| `HImageMock` | `init(url:data:delay:)`, `init(url:error:delay:)`; `url`, `data`, `error`, `delay` |

## Cache

| Type | Role |
|---|---|
| `HImageCache` | Namespace: `Configuration` (`expirationTime`, `maxObjectSizeInMBs`, `memoryCacheCapacityInMBs`, `diskCacheCapacityInMBs`, `storesOriginalWhenProcessed`, `directory`) and `Scope` (`.memory`, `.disk`, `.all`) |
| `HImageCacheType` | `.memoryAndDisk`, `.memoryOnly`, `.diskOnly`, `.disabled` |
| `HImageCachePolicy` | `.useCache`, `.reloadIgnoringCache`, `.returnCacheDontLoad` |

## Processing and encoding (`processing.md`)

| Type | Factory | Configuration |
|---|---|---|
| `HImageProcessor` | protocol | `identifier`, `process(_:context:)` |
| `HImageProcessingContext` | `init(format:targetSize:)` (to test a custom processor) | `format`, `targetSize` |
| `HResizeProcessor` (`Mode`: `.fit`, `.fill`, `.stretch`) | `.resize(to:mode:allowsUpscaling:)` | `size`, `mode`, `allowsUpscaling` |
| `HCropProcessor` (`Region`: `.rect`, `.size(_:alignment:)`) | `.crop(rect:)`, `.crop(size:alignment:)` | `region` |
| `HMaskProcessor` | `.mask(_:)`, `.roundedCorners(_:)` | `shape` |
| `HImageMaskShape` | `.circle`, `.ellipse`, `.capsule`, `.roundedRect(radius:)`, `.path(_:id:)`, `.image(_:id:)` | |
| `HBorderProcessor` | `.border(width:color:shape:)` | `width`, `color`, `shape` |
| `HRotateProcessor` | `.rotate(degrees:)` | `degrees` (normalized to `0..<360`) |
| `HFlipProcessor` (`Direction`: `.horizontal`, `.vertical`) | `.flip(_:)` | `direction` |
| `HPaddingProcessor` | `.padding(_:color:)` | `insets`, `color` |
| `HBlurProcessor` | `.blur(radius:)` | `radius` |
| `HTintProcessor` | `.tint(_:)` | `color` |
| `HColorAdjustProcessor` | `.adjust(brightness:contrast:saturation:)`, `.grayscale` | `brightness`, `contrast`, `saturation` |
| `HOverlayProcessor` | `.overlay(_:id:alignment:relativeWidth:margin:opacity:)` | `overlay`, `id`, `alignment`, `relativeWidth`, `margin`, `opacity` |
| `HImageColor` | `.black`, `.white`, `.clear`, `init(red:green:blue:alpha:)`, `init?(cgColor:)` | |
| `HImageAlignment` | `.topLeading` … `.bottomTrailing`, `.center` | |
| `HImageEdgeInsets` | `init(top:leading:bottom:trailing:)`, `init(all:)` | |
| `HImageEncoding` (`Format`: `.jpeg`, `.png`, `.heic`) | `.jpeg(quality:maxBytes:)`, `.png`, `.heic(quality:maxBytes:)`, `init(format:quality:maxBytes:)` | `format`, `quality`, `maxBytes` |

## SwiftUI

| Type | Role |
|---|---|
| `HImageView` | The view; initializers and modifiers in `examples.md` |
| `HImagePhase` | `.empty(progress:)`, `.success(Image)`, `.failure(HImageError)`; `image`, `error` accessors |
| `HImageTransition` | `.none`, `.fade(duration:)`, `.scale(from:duration:)`, `.blur(radius:duration:)`, `.custom(_:animation:)` |
| `HAnimatedImagePlayback` | `isEnabled`, `loopCount`, `speed`; `.automatic`, `.disabled` |
| `View.hImagePrefetch(_:destination:)` | Prefetches while the view is on screen |

## Prefetching

| Type | Role |
|---|---|
| `HImagePrefetcher` (`Destination`: `.disk`, `.memoryAndDisk`) | `init(maxConcurrent:destination:)`, `prefetch(_:)`, `start(_:)`, `cancel()` (isolated to `@HRequestManagerActor`: `await` its methods) |
| `HImagePrefetchReport` | `completed`, `failed`, `cancelled` |
