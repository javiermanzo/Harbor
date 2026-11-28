//
//  HarborImage.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// Entry point of the HarborImage module: global image configuration and the direct calls
/// that load images without a view.
///
/// Network-level settings (timeouts, auth provider, default headers, mTLS, SSL pinning, custom
/// session, logging) are shared with the other products and configured through `Harbor`. Images
/// are shown with `HImageView`, or loaded directly:
///
/// ```swift
/// // async
/// let response = await HarborImage.image(for: HImageRequest(url: "https://cdn.example.com/a.jpg"))
///
/// // async, with an optional callback
/// let response = await HarborImage.image(for: request, onEvent: { event in
///     if case .progress(let fraction) = event { progress = fraction }
/// })
///
/// // From code without an async context, a Task: cancelling it cancels the load
/// let task = Task {
///     let response = await HarborImage.image(for: request)
///     imageView.image = response.result.map { UIImage(cgImage: $0.image) }
/// }
/// ```
@HRequestManagerActor
public enum HarborImage {}

// MARK: - Configuration

public extension HarborImage {
    /// Sets the sizes and lifetime of the cache. A capacity lowered below the current use evicts
    /// entries as images are stored; the memory capacity applies at once.
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    /// - Parameter configuration: The cache configuration.
    static func setCacheConfiguration(_ configuration: HImageCache.Configuration) {
        HImageConfig.shared.cacheConfiguration = configuration
        HImageMemoryCache.shared.setCapacity(configuration.memoryCapacityInBytes)
    }

    /// Sets where images are cached when the request leaves `cacheType` as `nil`. Default: `.memoryAndDisk`.
    /// - Parameter cacheType: The default cache type.
    static func setDefaultCacheType(_ cacheType: HImageCacheType) {
        HImageConfig.shared.defaultCacheType = cacheType
    }

    /// Sets the retry policy of requests that leave `retryPolicy` as `nil`. Default: `nil`, no retries.
    /// - Parameter retryPolicy: The default retry policy.
    static func setDefaultRetryPolicy(_ retryPolicy: HRetryPolicy?) {
        HImageConfig.shared.defaultRetryPolicy = retryPolicy
    }

    /// Sets the largest download accepted, checked against `Content-Length` and while the body
    /// arrives; a larger one fails with `.tooLarge`. It applies to successful responses only
    /// (the body of an error status is discarded), and not to `data:` and `file:` URLs nor to
    /// mocks. Default: 30 MB. Values below 1 are clamped to 1.
    /// - Parameter megabytes: The limit in megabytes.
    static func setMaxDownloadSizeInMBs(_ megabytes: Int) {
        HImageConfig.shared.maxDownloadSizeInBytes = min(max(1, megabytes), Int.max / (1024 * 1024)) * 1024 * 1024
    }

    /// Sets the largest image accepted, in pixels, checked before decoding so a small file that
    /// decodes to a huge bitmap (a decompression bomb) fails with `.tooManyPixels` instead of
    /// exhausting memory. An SVG is checked before it is rasterized; an image from a registered
    /// `HImageDecoder` only after decoding. Default: 100 megapixels. Values below 1 are clamped to 1.
    /// - Parameter pixels: The limit in pixels.
    static func setMaxImagePixels(_ pixels: Int) {
        HImageConfig.shared.maxImagePixels = max(1, pixels)
    }

    /// Sets how many downloads run at once; the others wait in order. Default: 6. Values below 1 are clamped to 1.
    /// - Parameter count: The number of downloads.
    static func setMaxConcurrentDownloads(_ count: Int) {
        HImageConfig.shared.maxConcurrentDownloads = max(1, count)
    }

    /// Registers a decoder for a format HarborImage does not decode itself. Registered decoders
    /// are asked first, in registration order.
    /// - Parameter decoder: The decoder.
    static func registerDecoder(_ decoder: any HImageDecoder) {
        HImageConfig.shared.decoders.append(decoder)
    }

    /// Removes every registered decoder.
    static func removeAllDecoders() {
        HImageConfig.shared.decoders.removeAll()
    }
}

// MARK: - Mocks

public extension HarborImage {
    /// Enables or disables the registered mocks. Default: `true`. Mocks are never served in
    /// release builds, whatever this setting says.
    /// - Parameter enabled: Whether mocks are served.
    static func setMocksEnabled(_ enabled: Bool) {
        HImageConfig.shared.mocksEnabled = enabled
    }

    /// Registers a mock; it replaces any mock for the same URL.
    /// - Parameter mock: The mock.
    static func register(_ mock: HImageMock) {
        HImageConfig.shared.mocks[mock.url] = mock
    }

    /// Removes every registered mock.
    static func removeAllMocks() {
        HImageConfig.shared.mocks.removeAll()
    }
}
