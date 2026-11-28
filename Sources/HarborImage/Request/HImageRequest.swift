//
//  HImageRequest.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// A ready-made `HImageRequestProtocol` for the common case, so loading an image does not need
/// a dedicated type:
///
/// ```swift
/// let request = HImageRequest(url: "https://cdn.example.com/a.jpg",
///                             processors: [.resize(to: CGSize(width: 400, height: 400), mode: .fit)])
/// let response = await HarborImage.image(for: request)
/// ```
public struct HImageRequest: HImageRequestProtocol {
    /// The image URL: `http`, `https`, `data:` or `file:`. Path parameters are written as `{name}`.
    public var url: String
    /// Values substituted into the `{name}` placeholders of `url`.
    public var pathParameters: [String: String]?
    /// Query items appended to the URL.
    public var queryParameters: [String: String]?
    /// Headers sent with the download, on top of `Harbor`'s default headers.
    public var headerParameters: [String: String]?
    /// Whether the download needs the auth provider's header.
    public var needsAuth: Bool
    /// Retry policy for the download; `nil` uses the default one.
    public var retryPolicy: HRetryPolicy?
    /// Timeout of the download in seconds; `nil` uses Harbor's default timeout.
    public var timeoutInterval: TimeInterval?
    /// Where the image is cached; `nil` uses the default cache type.
    public var cacheType: HImageCacheType?
    /// Whether the cache is read before downloading.
    public var cachePolicy: HImageCachePolicy
    /// The key the image is cached under instead of the URL.
    public var cacheKey: String?
    /// Names of query items left out of the cache key.
    public var ignoredQueryParameters: Set<String>
    /// Processors applied, in order, to the decoded image.
    public var processors: [any HImageProcessor]
    /// The encoding of the result's data and of the processed variant stored on disk.
    public var encoding: HImageEncoding?
    /// The size the image is decoded at, in pixels.
    public var targetSize: HImageTargetSize?
    /// URLs tried, in order, when `url` fails (see `HImageRequestProtocol.fallbackURLs`).
    public var fallbackURLs: [String]

    /// Creates a request. Every parameter but `url` has the default of `HImageRequestProtocol`.
    /// - Parameters:
    ///   - url: The image URL.
    ///   - pathParameters: Values substituted into the `{name}` placeholders of `url`.
    ///   - queryParameters: Query items appended to the URL.
    ///   - headerParameters: Headers sent with the download.
    ///   - needsAuth: Whether the download needs the auth provider's header.
    ///   - retryPolicy: Retry policy for the download.
    ///   - timeoutInterval: Timeout of the download in seconds.
    ///   - cacheType: Where the image is cached.
    ///   - cachePolicy: Whether the cache is read before downloading.
    ///   - cacheKey: The key the image is cached under instead of the URL.
    ///   - ignoredQueryParameters: Names of query items left out of the cache key.
    ///   - processors: Processors applied, in order, to the decoded image.
    ///   - encoding: The encoding of the result's data and of the processed variant on disk.
    ///   - targetSize: The size the image is decoded at, in pixels.
    ///   - fallbackURLs: URLs tried when the download of `url` fails.
    public init(url: String,
                pathParameters: [String: String]? = nil,
                queryParameters: [String: String]? = nil,
                headerParameters: [String: String]? = nil,
                needsAuth: Bool = false,
                retryPolicy: HRetryPolicy? = nil,
                timeoutInterval: TimeInterval? = nil,
                cacheType: HImageCacheType? = nil,
                cachePolicy: HImageCachePolicy = .useCache,
                cacheKey: String? = nil,
                ignoredQueryParameters: Set<String> = [],
                processors: [any HImageProcessor] = [],
                encoding: HImageEncoding? = nil,
                targetSize: HImageTargetSize? = nil,
                fallbackURLs: [String] = []) {
        self.url = url
        self.pathParameters = pathParameters
        self.queryParameters = queryParameters
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.retryPolicy = retryPolicy
        self.timeoutInterval = timeoutInterval
        self.cacheType = cacheType
        self.cachePolicy = cachePolicy
        self.cacheKey = cacheKey
        self.ignoredQueryParameters = ignoredQueryParameters
        self.processors = processors
        self.encoding = encoding
        self.targetSize = targetSize
        self.fallbackURLs = fallbackURLs
    }
}
