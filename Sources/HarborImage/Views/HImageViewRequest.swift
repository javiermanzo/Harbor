//
//  HImageViewRequest.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// The request an `HImageView` loads: its request with the view's modifiers applied
/// (`.processors`, `.encoding`, `.cacheType`, `.retryPolicy`, `.downsampling`, ...).
struct HImageViewRequest: HImageRequestProtocol {
    /// The request given to the view.
    let base: any HImageRequestProtocol
    /// Processors set with `.processors(_:)`, replacing the request's.
    var processorsOverride: [any HImageProcessor]?
    /// Encoding set with `.encoding(_:)`.
    var encodingOverride: HImageEncoding?
    /// Cache type set with `.cacheType(_:)`.
    var cacheTypeOverride: HImageCacheType?
    /// Cache policy set with `.cachePolicy(_:)`.
    var cachePolicyOverride: HImageCachePolicy?
    /// Retry policy set with `.retryPolicy(_:)`.
    var retryPolicyOverride: HRetryPolicy?
    /// Decoding size set with `.downsampling(to:contentMode:)`, in pixels.
    var targetSizeOverride: HImageTargetSize?

    /// Wraps the request of a view.
    /// - Parameter base: The request.
    init(base: any HImageRequestProtocol) {
        self.base = base
    }
}

// MARK: - HImageRequestProtocol

extension HImageViewRequest {
    /// The request's URL.
    var url: String { base.url }
    /// The request's path parameters.
    var pathParameters: [String: String]? { base.pathParameters }
    /// The request's query parameters.
    var queryParameters: [String: String]? { base.queryParameters }
    /// The request's headers.
    var headerParameters: [String: String]? { base.headerParameters }
    /// The request's auth flag.
    var needsAuth: Bool { base.needsAuth }
    /// The view's retry policy, or the request's.
    var retryPolicy: HRetryPolicy? { retryPolicyOverride ?? base.retryPolicy }
    /// The request's timeout.
    var timeoutInterval: TimeInterval? { base.timeoutInterval }
    /// The view's cache type, or the request's.
    var cacheType: HImageCacheType? { cacheTypeOverride ?? base.cacheType }
    /// The view's cache policy, or the request's.
    var cachePolicy: HImageCachePolicy { cachePolicyOverride ?? base.cachePolicy }
    /// The request's cache key.
    var cacheKey: String? { base.cacheKey }
    /// The request's ignored query parameters.
    var ignoredQueryParameters: Set<String> { base.ignoredQueryParameters }
    /// The view's processors, or the request's.
    var processors: [any HImageProcessor] { processorsOverride ?? base.processors }
    /// The view's encoding, or the request's.
    var encoding: HImageEncoding? { encodingOverride ?? base.encoding }
    /// The view's decoding size, or the request's.
    var targetSize: HImageTargetSize? { targetSizeOverride ?? base.targetSize }
    /// The request's fallback URLs.
    var fallbackURLs: [String] { base.fallbackURLs }
}
