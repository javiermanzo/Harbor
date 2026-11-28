//
//  HarborImage+Loading.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation
import HarborCore

// MARK: - Loading

public extension HarborImage {
    /// Loads an image: memory cache, disk cache, then the network. Concurrent loads of the same
    /// image share one download. Never throws: a failure is `.failure(HImageError)`.
    ///
    /// Cancelling the calling task returns `.failure(.cancelled)` at once and stops delivering
    /// events; the download itself stops only when no other caller is waiting for it.
    /// - Parameters:
    ///   - request: The image to load.
    ///   - onEvent: An optional callback receiving the events of the load on the main actor.
    ///     Every event is delivered before this function returns.
    /// - Returns: The image, or the reason it could not be loaded.
    static func image(for request: some HImageRequestProtocol, onEvent: HImageEventHandler? = nil) async -> HImageResponse {
        let relay = onEvent.map(HImageEventRelay.init)
        let response = await withTaskCancellationHandler {
            await loadImage(for: request, sink: relay?.sink)
        } onCancel: {
            relay?.cancel()
        }
        if Task.isCancelled {
            relay?.cancel()
            return .failure(.cancelled)
        }
        await relay?.drain()
        return response
    }

    /// Loads the original bytes of an image, checked to be an image (by its signature) but
    /// neither decoded nor processed: to save, share or upload it. It reads and fills the disk
    /// cache (never the memory cache), following the request's `cacheType` and `cachePolicy`.
    /// Concurrent loads of the same URL, bytes or image, share one download.
    /// - Parameters:
    ///   - request: The image to load; its processors and encoding are ignored.
    ///   - onEvent: An optional callback receiving `started`, `progress`, `retrying` and
    ///     `loaded` on the main actor (there is no `finished` event: the bytes are the return value).
    /// - Returns: The bytes, or the reason they could not be loaded.
    static func data(for request: some HImageRequestProtocol, onEvent: HImageEventHandler? = nil) async -> HImageDataResponse {
        let relay = onEvent.map(HImageEventRelay.init)
        let response: HImageDataResponse
        do {
            let resolved = try resolve(request)
            response = await withTaskCancellationHandler {
                await HImageLoader.data(for: resolved, sink: relay?.sink)
            } onCancel: {
                relay?.cancel()
            }
        } catch {
            relay?.sink(.started)
            response = .failure(error)
        }
        if Task.isCancelled {
            relay?.cancel()
            return .failure(.cancelled)
        }
        await relay?.drain()
        return response
    }

    /// The events of a load as an asynchronous sequence, an alternative to callbacks. The load
    /// starts when this is called (events are buffered until read) and is cancelled when the
    /// sequence is no longer iterated.
    /// - Parameter request: The image to load.
    /// - Returns: The events, ending after `finished`.
    nonisolated static func events(for request: some HImageRequestProtocol) -> AsyncStream<HImageEvent> {
        AsyncStream { continuation in
            let task = Task {
                _ = await loadImage(for: request, sink: { continuation.yield($0) })
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Loads an image with an internal event sink.
    /// - Parameters:
    ///   - request: The image to load.
    ///   - sink: Receives the events.
    internal static func loadImage(for request: some HImageRequestProtocol, sink: HImageEventSink?) async -> HImageResponse {
        do {
            return await HImageLoader.image(for: try resolve(request), sink: sink)
        } catch {
            let response = HImageResponse.failure(error)
            sink?(.started)
            sink?(.finished(response))
            return response
        }
    }

    /// Resolves a request against the configuration.
    /// - Parameter request: The request.
    internal static func resolve(_ request: some HImageRequestProtocol) throws(HImageError) -> HImageResolvedRequest {
        try HImageResolvedRequest(request: request,
                                  defaultCacheType: HImageConfig.shared.defaultCacheType,
                                  defaultRetryPolicy: HImageConfig.shared.defaultRetryPolicy)
    }
}

// MARK: - Cache

public extension HarborImage {
    /// The cached image, from memory or disk (even expired), without downloading. A `data:` or
    /// `file:` URL is decoded instead.
    /// - Parameter request: The image.
    /// - Returns: The image, or `nil` when it is not cached.
    static func cached(for request: some HImageRequestProtocol) async -> HImageResult? {
        guard var resolved = try? resolve(request) else { return nil }
        resolved.cachePolicy = .returnCacheDontLoad
        return await HImageLoader.image(for: resolved, sink: nil).result
    }

    /// Stores image bytes in the disk cache as the original of the request (an image the app
    /// just uploaded, for example). Every cached copy of the image is dropped first, in memory
    /// and on disk, for every size and processing, so the next load renders the new bytes; a
    /// load already in flight does not store over them.
    /// - Parameters:
    ///   - data: The image bytes.
    ///   - request: The image they are for.
    /// - Returns: `false` when nothing was stored: the bytes are not an image, the request URL
    ///   is invalid, the request's cache type does not use the disk (`.memoryOnly`, `.disabled`),
    ///   or the bytes are larger than `maxObjectSizeInMBs`.
    @discardableResult
    static func store(_ data: Data, for request: some HImageRequestProtocol) async -> Bool {
        guard let resolved = try? resolve(request), resolved.cacheType.usesDisk,
              (try? HImagePipeline.detectFormat(data, decoders: HImageConfig.shared.decoders)) != nil else {
            return false
        }
        let originalKey = resolved.key.original
        let configuration = HImageConfig.shared.cacheConfiguration
        await removeCachedCopies(of: originalKey, configuration: configuration)
        let generation = HImageLoader.Generation.current(for: originalKey)
        return await HImageDiskCache.shared.store(data, for: resolved.key.originalOnDisk, configuration: configuration) {
            generation == .current(for: originalKey)
        }
    }

    /// Removes every cached copy of the request's image: its decoded images in memory and its
    /// original bytes and processed variants on disk, for every size and processing. A load
    /// already in flight does not store what it downloads.
    /// - Parameter request: The image.
    static func remove(_ request: some HImageRequestProtocol) async {
        guard let resolved = try? resolve(request) else { return }
        await removeCachedCopies(of: resolved.key.original, configuration: HImageConfig.shared.cacheConfiguration)
    }

    /// Empties the cache. Call it whenever the signed-in account changes: entries are keyed by
    /// URL only and shared by every account. A load that started before the call does not store
    /// what it downloads.
    /// - Parameter scope: The layers to empty. Default: `.all`.
    static func clearCache(_ scope: HImageCache.Scope = .all) async {
        HImageConfig.shared.cacheGeneration &+= 1
        if scope != .disk {
            HImageMemoryCache.shared.removeAll()
        }
        if scope != .memory {
            await HImageDiskCache.shared.removeAll(configuration: HImageConfig.shared.cacheConfiguration)
        }
    }

    /// The size of the disk cache in bytes.
    static func diskCacheSize() async -> Int {
        await HImageDiskCache.shared.size(configuration: HImageConfig.shared.cacheConfiguration)
    }

    /// The number of files in the disk cache.
    static func diskCacheCount() async -> Int {
        await HImageDiskCache.shared.count(configuration: HImageConfig.shared.cacheConfiguration)
    }
    /// Drops every cached copy of an image and invalidates the loads in flight for it.
    /// - Parameters:
    ///   - originalKey: The original cache key of the image.
    ///   - configuration: The cache configuration.
    private static func removeCachedCopies(of originalKey: String, configuration: HImageCache.Configuration) async {
        HImageLoader.bumpRevision(of: originalKey)
        HImageMemoryCache.shared.removeImage(originalKey: originalKey)
        await HImageDiskCache.shared.removeImage(originalKey: originalKey, configuration: configuration)
    }
}

// MARK: - Processing Without Download

public extension HarborImage {
    /// Runs processors on an image the app already has (from the camera or the photo library),
    /// off the main actor.
    /// - Parameters:
    ///   - image: The image.
    ///   - processors: The processors, applied in order.
    /// - Returns: The processed image.
    /// - Throws: The `HImageError` a processor threw, `.cancelled` when the task is cancelled,
    ///   or `.processingFailed` for any other error.
    nonisolated static func process(_ image: CGImage, with processors: [any HImageProcessor]) async throws(HImageError) -> CGImage {
        try await HImagePipeline.process(image, with: processors)
    }

    /// Encodes an image (compression and format conversion) without downloading anything: to
    /// upload a photo under a size limit, for example.
    /// - Parameters:
    ///   - image: The image.
    ///   - encoding: The format, quality and size limit.
    /// - Returns: The encoded bytes.
    /// - Throws: `HImageError.encodingFailed` when the format is unavailable or `maxBytes` cannot be met.
    nonisolated static func encode(_ image: CGImage, as encoding: HImageEncoding) async throws(HImageError) -> Data {
        try HImageEncoder.encode(image, as: encoding)
    }
}
