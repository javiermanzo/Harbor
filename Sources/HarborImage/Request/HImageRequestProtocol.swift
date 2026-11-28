//
//  HImageRequestProtocol.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

// MARK: - HImageRequestProtocol

/// A remote (or `data:` / `file:`) image. Conform a `Sendable` struct to it, set `url`, and load
/// it with `HImageView` or `HarborImage.image(for:onEvent:)`.
/// `HImageRequest` covers the common case without declaring a type.
///
/// The download goes through Harbor's pipeline: connectivity check, auth provider (with the
/// same `401` refresh flow as REST requests), default headers, retry policy, SSL pinning, mTLS,
/// redirect policy and custom session. The result is decoded, processed and cached in memory
/// and on disk by HarborImage.
///
/// ```swift
/// struct AvatarRequest: HImageRequestProtocol {
///     let url = "https://api.example.com/users/{id}/avatar"
///     let pathParameters: [String: String]?
///     let needsAuth = true
///     var processors: [any HImageProcessor] { [.resize(to: CGSize(width: 120, height: 120), mode: .fill), .mask(.circle)] }
///
///     init(userId: Int) {
///         pathParameters = ["id": String(userId)]
///     }
/// }
/// ```
public protocol HImageRequestProtocol: Sendable {
    /// The image URL: `http`, `https`, `data:` or `file:`. Path parameters are written as `{name}`.
    var url: String { get }

    /// Values substituted into the `{name}` placeholders of `url`. Default: `nil`.
    var pathParameters: [String: String]? { get }

    /// Query items appended to the URL. Default: `nil`.
    var queryParameters: [String: String]? { get }

    /// Headers sent with the download, on top of `Harbor`'s default headers. Default: `nil`.
    var headerParameters: [String: String]? { get }

    /// Whether the download needs the auth provider's header. Default: `false`.
    ///
    /// The authorization header is never part of the cache key: an image downloaded with
    /// credentials is shared by every account. Use `.memoryOnly` or `.disabled` for private
    /// images, and call `HarborImage.clearCache()` when the signed-in account changes.
    var needsAuth: Bool { get }

    /// Retry policy for the download. Default: `nil`, the policy set with
    /// `HarborImage.setDefaultRetryPolicy(_:)` (no retries unless configured).
    var retryPolicy: HRetryPolicy? { get }

    /// Timeout of the download in seconds. Default: `nil`, Harbor's default timeout
    /// (`Harbor.setDefaultTimeoutInterval(_:)`).
    var timeoutInterval: TimeInterval? { get }

    /// Where the image is cached. Default: `nil`, the type set with
    /// `HarborImage.setDefaultCacheType(_:)` (`.memoryAndDisk` unless configured).
    var cacheType: HImageCacheType? { get }

    /// Whether the cache is read before downloading. Default: `.useCache`.
    var cachePolicy: HImageCachePolicy { get }

    /// The key the image is cached under, instead of the URL. Default: `nil`, the composed URL.
    ///
    /// Use it for signed URLs (`?Expires=...&Signature=...`), whose query changes on every
    /// request and would otherwise never hit the cache. Never put a credential in it.
    var cacheKey: String? { get }

    /// Names of query items left out of the cache key (the URL still sends them). An
    /// alternative to `cacheKey` for signed URLs. Default: `[]`.
    var ignoredQueryParameters: Set<String> { get }

    /// Processors applied, in order, to the decoded image. Their identifiers are part of the
    /// cache key, so each processed variant is cached separately. Default: `[]`.
    var processors: [any HImageProcessor] { get }

    /// The encoding of `HImageResult.data` and of the processed variant stored on disk
    /// (compression and format conversion). Default: `nil`, the original bytes when there are
    /// no processors or the image is animated or an SVG, a PNG otherwise.
    var encoding: HImageEncoding? { get }

    /// The size the image is decoded at (downsampling), in pixels. Decoding a large image at
    /// the size it is displayed at uses a fraction of the memory. Default: `nil`, the size of a
    /// first `.resize(to:)` processor, or the full size.
    var targetSize: HImageTargetSize? { get }

    /// URLs tried, in order, when `url` fails (after its retries) with an HTTP error, a
    /// transport error or a timeout, or with bytes that are too large, not an image or cannot be
    /// decoded. They are not tried after `.noConnection`, auth, certificate, cancellation,
    /// processing or encoding errors. The result is cached under the key of `url`. Default: `[]`.
    var fallbackURLs: [String] { get }
}

// MARK: - Default Implementations

/// Default property implementations for `HImageRequestProtocol`.
public extension HImageRequestProtocol {
    /// Default: `nil`, no path parameters.
    var pathParameters: [String: String]? { nil }
    /// Default: `nil`, no query items.
    var queryParameters: [String: String]? { nil }
    /// Default: `nil`, no additional headers.
    var headerParameters: [String: String]? { nil }
    /// Default: `false`, the download is sent without consulting the auth provider.
    var needsAuth: Bool { false }
    /// Default: `nil`, the policy set with `HarborImage.setDefaultRetryPolicy(_:)`.
    var retryPolicy: HRetryPolicy? { nil }
    /// Default: `nil`, Harbor's default timeout.
    var timeoutInterval: TimeInterval? { nil }
    /// Default: `nil`, the type set with `HarborImage.setDefaultCacheType(_:)`.
    var cacheType: HImageCacheType? { nil }
    /// Default: `.useCache`.
    var cachePolicy: HImageCachePolicy { .useCache }
    /// Default: `nil`, the composed URL.
    var cacheKey: String? { nil }
    /// Default: `[]`, every query item is part of the cache key.
    var ignoredQueryParameters: Set<String> { [] }
    /// Default: `[]`, the image is not processed.
    var processors: [any HImageProcessor] { [] }
    /// Default: `nil`, no re-encoding.
    var encoding: HImageEncoding? { nil }
    /// Default: `nil`, no explicit downsampling.
    var targetSize: HImageTargetSize? { nil }
    /// Default: `[]`, no fallback.
    var fallbackURLs: [String] { [] }
}
