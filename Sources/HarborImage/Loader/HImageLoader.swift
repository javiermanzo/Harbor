//
//  HImageLoader.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// Runs image loads: memory cache, deduplication, disk cache, network (through Harbor's shared
/// pipeline: auth, retry, pinning, mTLS), decoding, processing and storage. Isolated to Harbor's
/// global actor so it reads the shared configuration safely; decoding and processing run off
/// the actor (`HImagePipeline`).
@HRequestManagerActor
enum HImageLoader {
    /// The image loads in flight, by generations, cache settings and memory key.
    static var imageFlights: [String: HImageFlight<HImageResponse>] = [:]
    /// The byte loads (`data(for:)`) in flight, by generations, cache settings and original key.
    static var dataFlights: [String: HImageFlight<HImageDataResponse>] = [:]
    /// The downloads in flight, shared by image and byte loads (see `downloadKey`).
    static var downloadFlights: [String: HImageFlight<Result<HImageDownload, HImageError>>] = [:]
    /// How many times each original key was stored or removed (`HarborImage.store(_:for:)`,
    /// `remove(_:)`); only keys that ever were are present.
    static var revisions: [String: Int] = [:]
    /// Limits the downloads running at once.
    static let limiter = HImageLimiter()
}

// MARK: - Generations

extension HImageLoader {
    /// What a load started with: the cache generation (`clearCache`), the auth generation
    /// (`Harbor.setAuthProvider`) and the revision of its image (`store`, `remove`). A load that
    /// finishes after any of them changed returns its image but does not store it, and a load
    /// that starts after a change never joins one that started before.
    struct Generation: Equatable {
        /// `HImageConfig.cacheGeneration`.
        let cache: Int
        /// `HRequestManager.authGeneration`.
        let auth: Int
        /// The revision of the image's original key.
        let revision: Int

        /// The current generations for an image.
        /// - Parameter originalKey: The original cache key of the image.
        @HRequestManagerActor static func current(for originalKey: String) -> Generation {
            Generation(cache: HImageConfig.shared.cacheGeneration,
                       auth: HRequestManager.authGeneration,
                       revision: HImageLoader.revisions[originalKey, default: 0])
        }

        /// The generations as part of a flight key.
        var identifier: String {
            "\(cache).\(auth).\(revision)"
        }
    }

    /// Records that the cached copies of an image were replaced or removed, so loads in flight
    /// do not store over them.
    /// - Parameter originalKey: The original cache key of the image.
    static func bumpRevision(of originalKey: String) {
        revisions[originalKey, default: 0] &+= 1
    }

    /// The pipeline settings from the configuration.
    static var settings: HImagePipeline.Settings {
        HImagePipeline.Settings(decoders: HImageConfig.shared.decoders, maxImagePixels: HImageConfig.shared.maxImagePixels)
    }
}

// MARK: - Image

extension HImageLoader {
    /// Loads an image.
    /// - Parameters:
    ///   - resolved: The request.
    ///   - sink: Receives the events of the load.
    static func image(for resolved: HImageResolvedRequest, sink: HImageEventSink?) async -> HImageResponse {
        sink?(.started)
        let response = await loadImage(for: resolved, sink: sink)
        if case .success(let result) = response {
            sink?(.loaded(source: result.source))
        }
        sink?(.finished(response))
        return response
    }

    /// Loads an image: memory first, then a shared flight.
    /// - Parameters:
    ///   - resolved: The request.
    ///   - sink: Receives the progress and retry events.
    private static func loadImage(for resolved: HImageResolvedRequest, sink: HImageEventSink?) async -> HImageResponse {
        if resolved.cachePolicy != .reloadIgnoringCache, resolved.cacheType.usesMemory,
           let cached = HImageMemoryCache.shared.result(forKey: resolved.key.memory) {
            return .success(cached.with(source: .memory))
        }
        guard !Task.isCancelled else { return .failure(.cancelled) }

        let flightKey = [Generation.current(for: resolved.key.original).identifier,
                         resolved.cachePolicy.rawValue,
                         resolved.cacheType.rawValue,
                         resolved.key.memory].joined(separator: "|")
        for _ in 0..<2 {
            let flight = imageFlight(forKey: flightKey, resolved: resolved)
            guard let id = flight.subscribe(sink: sink) else { continue }
            return await flight.wait(id: id)
        }
        return .failure(.cancelled)
    }

    /// The flight loading the key, started when there is none (or the previous one was abandoned).
    /// - Parameters:
    ///   - key: The flight key.
    ///   - resolved: The request.
    private static func imageFlight(forKey key: String, resolved: HImageResolvedRequest) -> HImageFlight<HImageResponse> {
        if let existing = imageFlights[key], !existing.isAbandoned {
            return existing
        }
        let flight = HImageFlight<HImageResponse>(cancelledResponse: .failure(.cancelled))
        imageFlights[key] = flight
        flight.attach(Task {
            let response = await run(resolved, flight: flight)
            if imageFlights[key] === flight {
                imageFlights[key] = nil
            }
            flight.finish(response)
        })
        return flight
    }

    /// The body of an image flight.
    /// - Parameters:
    ///   - resolved: The request.
    ///   - flight: The flight, to broadcast progress.
    private static func run(_ resolved: HImageResolvedRequest, flight: HImageFlight<HImageResponse>) async -> HImageResponse {
        let original = resolved.key.original
        let generation = Generation.current(for: original)
        let logContext = HImageLogContext(resolved: resolved)
        logContext?.logStart()

        let response = await fetchAndRender(resolved, flight: flight, generation: generation, settings: settings)
        if case .success(let result) = response, resolved.cacheType.usesMemory, generation == .current(for: original) {
            HImageMemoryCache.shared.store(result, forKey: resolved.key.memory, originalKey: original)
        }
        logContext?.logFinish(response)
        return response
    }

    /// Finds the image on disk or fetches it, then renders it. When the download fails for a
    /// transient reason (transport, timeout, `5xx`), an expired copy on disk is served instead.
    /// - Parameters:
    ///   - resolved: The request.
    ///   - flight: The flight, to broadcast progress.
    ///   - generation: The generations the load started with.
    ///   - settings: Decoders and limits.
    private static func fetchAndRender(_ resolved: HImageResolvedRequest, flight: HImageFlight<HImageResponse>, generation: Generation, settings: HImagePipeline.Settings) async -> HImageResponse {
        if resolved.isLocal {
            return await renderLocal(resolved, settings: settings)
        }

        let configuration = HImageConfig.shared.cacheConfiguration
        let isMocked = isMocked(resolved)
        let usesDisk = resolved.cacheType.usesDisk && !isMocked
        let isConnected = isMocked || resolved.cachePolicy == .returnCacheDontLoad || HRequestManager.connectivityMonitor.isConnectedToNetwork()
        let allowsExpired = !isConnected || resolved.cachePolicy == .returnCacheDontLoad

        if resolved.cachePolicy != .reloadIgnoringCache, usesDisk,
           let cached = await diskImage(resolved, configuration: configuration, allowsExpired: allowsExpired, generation: generation, settings: settings) {
            return cached
        }
        if resolved.cachePolicy == .returnCacheDontLoad {
            return .failure(.notCached)
        }
        if !isConnected {
            return .failure(.noConnection)
        }

        let response = await downloadAndRender(resolved, flight: flight, generation: generation, configuration: configuration, settings: settings)
        if case .failure(let error) = response, error.allowsStaleCopy, resolved.cachePolicy == .useCache, usesDisk,
           let stale = await diskImage(resolved, configuration: configuration, allowsExpired: true, generation: generation, settings: settings) {
            return stale
        }
        return response
    }

    /// Downloads the image, trying the fallback URLs in order, then renders and stores it.
    /// - Parameters:
    ///   - resolved: The request.
    ///   - flight: The flight, to broadcast progress.
    ///   - generation: The generations the load started with.
    ///   - configuration: The cache configuration.
    ///   - settings: Decoders and limits.
    private static func downloadAndRender(_ resolved: HImageResolvedRequest, flight: HImageFlight<HImageResponse>, generation: Generation, configuration: HImageCache.Configuration, settings: HImagePipeline.Settings) async -> HImageResponse {
        var lastError = HImageError.notAnImage
        for url in resolved.urls {
            let fetched: HImageDownload
            switch await sharedDownload(url: url, resolved: resolved, onEvent: { flight.broadcast($0) }) {
            case .success(let value):
                fetched = value
            case .failure(let error):
                guard error.allowsFallback else { return .failure(error) }
                lastError = error
                continue
            }

            do {
                let rendered = try await HImagePipeline.render(fetched.data, source: fetched.source, resolved: resolved, settings: settings)
                if resolved.cacheType.usesDisk, !fetched.forbidsStorage {
                    await storeOnDisk(rendered, original: fetched.data, resolved: resolved, configuration: configuration, generation: generation)
                }
                return .success(rendered.result)
            } catch {
                guard error.allowsFallback else { return .failure(error) }
                lastError = error
            }
        }
        return .failure(lastError)
    }

    /// Looks for the processed variant, then for the original bytes, on disk.
    /// - Parameters:
    ///   - resolved: The request.
    ///   - configuration: The cache configuration.
    ///   - allowsExpired: Whether an expired entry is used.
    ///   - generation: The generations the load started with.
    ///   - settings: Decoders and limits.
    private static func diskImage(_ resolved: HImageResolvedRequest, configuration: HImageCache.Configuration, allowsExpired: Bool, generation: Generation, settings: HImagePipeline.Settings) async -> HImageResponse? {
        let disk = HImageDiskCache.shared
        let key = resolved.key
        if key.isProcessed,
           let variant = await disk.data(for: key.variantOnDisk, configuration: configuration, allowsExpired: allowsExpired),
           let result = try? HImagePipeline.decodeVariant(variant, settings: settings) {
            return .success(result)
        }
        guard let original = await disk.data(for: key.originalOnDisk, configuration: configuration, allowsExpired: allowsExpired) else {
            return nil
        }
        do {
            let rendered = try await HImagePipeline.render(original, source: .disk, resolved: resolved, settings: settings)
            if let variant = rendered.variantData, generation == .current(for: key.original) {
                // The variant expires with the original it was rendered from.
                let storedAt = await disk.storedAt(for: key.originalOnDisk, configuration: configuration)
                await disk.store(variant, for: key.variantOnDisk, storedAt: storedAt, configuration: configuration) {
                    generation == .current(for: key.original)
                }
            }
            return .success(rendered.result)
        } catch {
            // Corrupted or no longer decodable: drop it and download again.
            guard error != .cancelled else { return .failure(.cancelled) }
            await disk.remove(key.originalOnDisk, configuration: configuration)
            return nil
        }
    }

    /// Stores what a download produced: the variant when there is one, and the original when
    /// there is no variant (no processing, an animated image or an SVG) or the configuration
    /// asks for it.
    /// - Parameters:
    ///   - rendered: The rendered image.
    ///   - original: The downloaded bytes.
    ///   - resolved: The request.
    ///   - configuration: The cache configuration.
    ///   - generation: The generations the load started with.
    private static func storeOnDisk(_ rendered: HImagePipeline.Rendered, original: Data, resolved: HImageResolvedRequest, configuration: HImageCache.Configuration, generation: Generation) async {
        let disk = HImageDiskCache.shared
        let key = resolved.key
        let isCurrent = { generation == .current(for: key.original) }
        if let variant = rendered.variantData {
            await disk.store(variant, for: key.variantOnDisk, configuration: configuration, isCurrent: isCurrent)
        }
        if rendered.variantData == nil || configuration.storesOriginalWhenProcessed {
            await disk.store(original, for: key.originalOnDisk, configuration: configuration, isCurrent: isCurrent)
        }
    }

    /// Renders a `data:` or `file:` URL.
    /// - Parameters:
    ///   - resolved: The request.
    ///   - settings: Decoders and limits.
    private static func renderLocal(_ resolved: HImageResolvedRequest, settings: HImagePipeline.Settings) async -> HImageResponse {
        guard let url = resolved.urls.first else { return .failure(.invalidURL(reason: "Missing URL")) }
        switch await localData(url) {
        case .failure(let error):
            return .failure(error)
        case .success(let data):
            do {
                return .success(try await HImagePipeline.render(data, source: .local, resolved: resolved, settings: settings).result)
            } catch {
                return .failure(error)
            }
        }
    }
}

// MARK: - Data

extension HImageLoader {
    /// Loads the original bytes of an image, checked to be an image but not decoded.
    /// - Parameters:
    ///   - resolved: The request.
    ///   - sink: Receives the events of the load.
    static func data(for resolved: HImageResolvedRequest, sink: HImageEventSink?) async -> HImageDataResponse {
        sink?(.started)
        let key = [Generation.current(for: resolved.key.original).identifier,
                   resolved.cachePolicy.rawValue,
                   resolved.cacheType.rawValue,
                   resolved.key.original].joined(separator: "|")
        var response = HImageDataResponse.failure(.cancelled)
        for _ in 0..<2 {
            let flight: HImageFlight<HImageDataResponse>
            if let existing = dataFlights[key], !existing.isAbandoned {
                flight = existing
            } else {
                flight = HImageFlight(cancelledResponse: .failure(.cancelled))
                dataFlights[key] = flight
                flight.attach(Task {
                    let result = await runData(resolved, flight: flight)
                    if dataFlights[key] === flight {
                        dataFlights[key] = nil
                    }
                    flight.finish(result)
                })
            }
            guard let id = flight.subscribe(sink: sink) else { continue }
            response = await flight.wait(id: id)
            break
        }
        if case .success(_, _, let source) = response {
            sink?(.loaded(source: source))
        }
        return response
    }

    /// The body of a byte flight.
    /// - Parameters:
    ///   - resolved: The request.
    ///   - flight: The flight, to broadcast progress.
    private static func runData(_ resolved: HImageResolvedRequest, flight: HImageFlight<HImageDataResponse>) async -> HImageDataResponse {
        let decoders = HImageConfig.shared.decoders
        if resolved.isLocal, let url = resolved.urls.first {
            switch await localData(url) {
            case .failure(let error):
                return .failure(error)
            case .success(let data):
                do {
                    return .success(data: data, format: try HImagePipeline.detectFormat(data, decoders: decoders), source: .local)
                } catch {
                    return .failure(error)
                }
            }
        }

        let generation = Generation.current(for: resolved.key.original)
        let configuration = HImageConfig.shared.cacheConfiguration
        let isMocked = isMocked(resolved)
        let usesDisk = resolved.cacheType.usesDisk && !isMocked
        let isConnected = isMocked || resolved.cachePolicy == .returnCacheDontLoad || HRequestManager.connectivityMonitor.isConnectedToNetwork()
        let allowsExpired = !isConnected || resolved.cachePolicy == .returnCacheDontLoad

        /// The original bytes on disk, when they are an image.
        func cachedOriginal(allowsExpired: Bool) async -> HImageDataResponse? {
            guard let data = await HImageDiskCache.shared.data(for: resolved.key.originalOnDisk, configuration: configuration, allowsExpired: allowsExpired),
                  let format = try? HImagePipeline.detectFormat(data, decoders: decoders) else {
                return nil
            }
            return .success(data: data, format: format, source: .disk)
        }

        /// An expired copy when the download failed for a transient reason, else the failure.
        func staleOrFailure(_ error: HImageError) async -> HImageDataResponse {
            if error.allowsStaleCopy, resolved.cachePolicy == .useCache, usesDisk, let stale = await cachedOriginal(allowsExpired: true) {
                return stale
            }
            return .failure(error)
        }

        if resolved.cachePolicy != .reloadIgnoringCache, usesDisk, let cached = await cachedOriginal(allowsExpired: allowsExpired) {
            return cached
        }
        if resolved.cachePolicy == .returnCacheDontLoad { return .failure(.notCached) }
        if !isConnected { return .failure(.noConnection) }

        var lastError = HImageError.notAnImage
        for url in resolved.urls {
            let fetched: HImageDownload
            switch await sharedDownload(url: url, resolved: resolved, onEvent: { flight.broadcast($0) }) {
            case .success(let value):
                fetched = value
            case .failure(let error):
                lastError = error
                if error.allowsFallback { continue }
                return await staleOrFailure(lastError)
            }
            do {
                let format = try HImagePipeline.detectFormat(fetched.data, decoders: decoders)
                if resolved.cacheType.usesDisk, !fetched.forbidsStorage {
                    await HImageDiskCache.shared.store(fetched.data, for: resolved.key.originalOnDisk, configuration: configuration) {
                        generation == .current(for: resolved.key.original)
                    }
                }
                return .success(data: fetched.data, format: format, source: fetched.source)
            } catch {
                lastError = error
            }
        }
        return await staleOrFailure(lastError)
    }
}
