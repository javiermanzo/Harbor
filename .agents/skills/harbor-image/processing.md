# Processing and encoding

Processors run off the main actor, in order, after decoding. They work on pixels (`CGImage → CGImage`, sizes in pixels, origin at the top left). The encoding is a separate last stage that produces bytes.

## Built-in processors

| Processor | Notes |
|---|---|
| `.resize(to:mode:allowsUpscaling:)` | `.fit`, `.fill` (covers, crops the excess around the center), `.stretch`. Never enlarges unless `allowsUpscaling`. As the first processor of a request without `targetSize`, it also downsamples while decoding. |
| `.crop(rect:)`, `.crop(size:alignment:)` | Limited to the image; outside it throws `.processingFailed`. The crop is redrawn, so it does not keep the full source image in memory. |
| `.mask(_:)` | `HImageMaskShape`: `.circle` (crops to the centered square first), `.ellipse`, `.roundedRect(radius:)`, `.capsule`, `.path(CGPath, id:)` (unit coordinates, top left origin), `.image(CGImage, id:)` (alpha of another image). Outside is transparent. |
| `.roundedCorners(_:)` | `.mask(.roundedRect(radius:))`. |
| `.border(width:color:shape:)` | Drawn inside the edges, following the shape; combine with a mask of the same shape. `.circle` is not cropped to a square here, so put `.mask(.circle)` before it. |
| `.rotate(degrees:)` | Clockwise; the canvas grows to fit, uncovered corners transparent. EXIF orientation is already applied while decoding. |
| `.flip(_:)` | `.horizontal` or `.vertical` mirror; same size. |
| `.padding(_:color:)` | `HImageEdgeInsets`, transparent or colored. |
| `.blur(radius:)` | Gaussian, edges extended. |
| `.tint(_:)` | Paints the opaque parts (templates). |
| `.grayscale`, `.adjust(brightness:contrast:saturation:)` | Core Image color controls. |
| `.overlay(_:id:alignment:relativeWidth:margin:opacity:)` | Watermarks, badges. |

Colors are `HImageColor` (sRGB components, `.black`, `.white`, `.clear`, `init?(cgColor:)`).

## Custom processors

```swift
struct SepiaProcessor: HImageProcessor {
    let intensity: Double
    var identifier: String { "sepia(\(intensity))" }   // stable, includes every parameter

    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        // context.format: format of the original (.png in HarborImage.process)
        // context.targetSize: the request's targetSize or its first resize; nil at full size
        ...
    }
}

HImageRequest(url: url, processors: [.resize(to: size, mode: .fill), SepiaProcessor(intensity: 0.8)])
```

- The identifier is part of the cache key: an unstable one (a memory address, a date) means the variant is never found in the cache.
- Throwing an `HImageError` reports it as-is; any other error becomes `.processingFailed("identifier: description")`. `CancellationError` becomes `.cancelled`.

## Processing without a download

```swift
let thumbnail = try await HarborImage.process(photo, with: [.resize(to: CGSize(width: 512, height: 512)), .grayscale])
```

## Encoding (compression and format conversion)

```swift
HImageRequest(url: url, processors: [.resize(to: CGSize(width: 1024, height: 1024))],
              encoding: .jpeg(quality: 0.8, maxBytes: 200_000))

let upload = try await HarborImage.encode(photo, as: .heic(quality: 0.7))
```

| Encoding | Notes |
|---|---|
| `.jpeg(quality:maxBytes:)` | Lossy, no alpha. |
| `.png` | Lossless, alpha. No quality to lower: with `HImageEncoding(format: .png, maxBytes:)` a larger output fails with `.encodingFailed`. |
| `.heic(quality:maxBytes:)` | Lossy, alpha. Not every device can encode it (`.encodingFailed`). |

- With `maxBytes` the quality is lowered (binary search down to 0.05, or to the requested quality when lower) until the output fits, or the load fails with `.encodingFailed`.
- Re-encoding never copies metadata (EXIF, GPS).
- WebP cannot be produced: ImageIO decodes WebP but has no encoder.

## What the result and the disk hold

| Request | `HImageResult.data` / `format` | Disk |
|---|---|---|
| No processors, no encoding | original bytes / original format | original |
| Processors, no encoding | PNG of the processed image / `.png` | processed variant (plus the original with `storesOriginalWhenProcessed`) |
| Encoding | encoded bytes / encoding format | encoded variant (plus the original with `storesOriginalWhenProcessed`) |
| Animated image or SVG, with processors or an encoding | original bytes / original format (encoded bytes / encoding format with an encoding) | original only (processed again on a disk hit) |
