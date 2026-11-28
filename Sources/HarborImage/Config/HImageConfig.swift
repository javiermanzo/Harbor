//
//  HImageConfig.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// Global configuration of the HarborImage module, set through `HarborImage`. Access is
/// serialized via `@HRequestManagerActor`, like Harbor's own configuration.
@HRequestManagerActor
struct HImageConfig {
    /// Shared singleton instance of the configuration.
    static var shared = HImageConfig()

    /// Sizes and lifetime of the cache.
    var cacheConfiguration = HImageCache.Configuration()
    /// Where images are cached when the request does not say.
    var defaultCacheType: HImageCacheType = .memoryAndDisk
    /// Retry policy of requests that do not set their own.
    var defaultRetryPolicy: HRetryPolicy?
    /// Largest download accepted, in bytes. Default: 30 MB.
    var maxDownloadSizeInBytes = 30 * 1024 * 1024
    /// Largest image accepted, in pixels, checked before decoding. Default: 100 megapixels.
    var maxImagePixels = 100_000_000
    /// Downloads running at once. Default: 6.
    var maxConcurrentDownloads = 6
    /// Decoders registered with `HarborImage.registerDecoder(_:)`, asked before the built-in ones.
    var decoders: [any HImageDecoder] = []
    /// Incremented by `HarborImage.clearCache(_:)`: a load that started before a clear does not
    /// store what it downloaded (the same rule applies to `Harbor.setAuthProvider(_:)`, through
    /// `HRequestManager.authGeneration`).
    var cacheGeneration = 0
    /// Whether registered mocks are served. Mocks are never served in release builds.
    var mocksEnabled = true
    /// Mocks registered with `HarborImage.register(_:)`, by URL.
    var mocks: [String: HImageMock] = [:]
}
