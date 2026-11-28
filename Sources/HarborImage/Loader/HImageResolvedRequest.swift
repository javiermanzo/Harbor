//
//  HImageResolvedRequest.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// A request with its URLs composed and the global defaults applied, read once on
/// `@HRequestManagerActor` and then used by the pipeline off the actor.
struct HImageResolvedRequest: Sendable {
    /// The original request (for headers, auth and logging).
    let request: any HImageRequestProtocol
    /// The image URL followed by the fallback URLs, composed.
    let urls: [URL]
    /// Where the image is cached.
    let cacheType: HImageCacheType
    /// Whether the cache is read before downloading.
    var cachePolicy: HImageCachePolicy
    /// The retry policy.
    let retryPolicy: HRetryPolicy?
    /// The processors.
    let processors: [any HImageProcessor]
    /// The encoding.
    let encoding: HImageEncoding?
    /// The size to decode at: the request's, or the one of a leading resize processor.
    let decodingTarget: HImageTargetSize?
    /// The cache keys.
    let key: HImageCacheKey
}

// MARK: - Resolution

extension HImageResolvedRequest {
    /// Schemes accepted in image URLs.
    static let allowedSchemes: Set<String> = ["http", "https", "data", "file"]

    /// Resolves the request: composes its URLs and applies the defaults.
    /// - Parameters:
    ///   - request: The request.
    ///   - defaultCacheType: The cache type used when the request sets none.
    ///   - defaultRetryPolicy: The retry policy used when the request sets none.
    /// - Throws: `.invalidURL` when the main URL cannot be built. Fallback URLs that cannot be
    ///   built are skipped.
    init(request: any HImageRequestProtocol, defaultCacheType: HImageCacheType, defaultRetryPolicy: HRetryPolicy?) throws(HImageError) {
        let main = try Self.compose(request.url, request: request)
        let fallbacks = request.fallbackURLs.compactMap { try? Self.compose($0, request: request) }
        self.request = request
        self.urls = [main] + fallbacks
        self.cacheType = request.cacheType ?? defaultCacheType
        self.cachePolicy = request.cachePolicy
        self.retryPolicy = request.retryPolicy ?? defaultRetryPolicy
        self.processors = request.processors
        self.encoding = request.encoding
        self.decodingTarget = request.targetSize ?? (request.processors.first as? HResizeProcessor)?.decodingTarget
        self.key = HImageCacheKey(url: main,
                                  cacheKey: request.cacheKey,
                                  ignoredQueryParameters: request.ignoredQueryParameters,
                                  processors: request.processors,
                                  encoding: request.encoding,
                                  targetSize: self.decodingTarget)
    }

    /// Composes one URL of the request. `data:` URLs are used as they are.
    /// - Parameters:
    ///   - url: The URL template.
    ///   - request: The request, for its path and query parameters.
    static func compose(_ url: String, request: any HImageRequestProtocol) throws(HImageError) -> URL {
        if url.lowercased().hasPrefix("data:") {
            guard let dataURL = URL(string: url) else { throw .invalidURL(reason: "Invalid data URL") }
            return dataURL
        }
        do {
            return try HURLBuilder.compositeURL(url: url,
                                                pathParameters: request.pathParameters,
                                                queryParameters: request.queryParameters,
                                                allowedSchemes: allowedSchemes)
        } catch let error as HRequestError {
            throw HImageError(pipelineError: error)
        } catch {
            throw .invalidURL(reason: String(describing: error))
        }
    }

    /// Whether the image comes from a `data:` or `file:` URL rather than the network.
    var isLocal: Bool {
        guard let scheme = urls.first?.scheme?.lowercased() else { return false }
        return scheme == "data" || scheme == "file"
    }

    /// The context handed to processors.
    /// - Parameter format: The format of the original image.
    func processingContext(format: HImageFormat) -> HImageProcessingContext {
        HImageProcessingContext(format: format, targetSize: decodingTarget)
    }
}
