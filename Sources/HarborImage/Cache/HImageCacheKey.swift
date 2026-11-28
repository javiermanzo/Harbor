//
//  HImageCacheKey.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// The keys an image is cached under. They are built from the URL (or the request's
/// `cacheKey`) and the processing only: never from a header, so no credential, nor a digest of
/// one, ever reaches a key or a file name.
struct HImageCacheKey: Sendable, Hashable {
    /// The key of the original bytes on disk: the URL (or `cacheKey`).
    let original: String
    /// The key of the processed variant on disk: the original key plus the processors, the
    /// encoding and the decoding size (a variant is rendered from the downsampled image, so each
    /// size is a different variant). Equal to `original` when there are no processors nor encoding.
    let variant: String
    /// The key of the decoded image in memory: the original key plus the processing and the
    /// decoding size.
    let memory: String

    /// Builds the keys of a request.
    /// - Parameters:
    ///   - url: The composed URL.
    ///   - cacheKey: The request's explicit key, if any.
    ///   - ignoredQueryParameters: Query item names left out of the key.
    ///   - processors: The processors.
    ///   - encoding: The encoding.
    ///   - targetSize: The decoding size.
    init(url: URL, cacheKey: String?, ignoredQueryParameters: Set<String>, processors: [any HImageProcessor], encoding: HImageEncoding?, targetSize: HImageTargetSize?) {
        let original = cacheKey ?? Self.canonicalURL(url, ignoring: ignoredQueryParameters)
        let size = targetSize?.identifier ?? "full"
        if processors.isEmpty, encoding == nil {
            self.variant = original
            self.memory = original + "|" + size
        } else {
            let steps = processors.map(\.identifier) + [encoding?.identifier ?? "-", size]
            self.variant = original + "|" + steps.joined(separator: "|")
            self.memory = self.variant
        }
        self.original = original
    }

    /// Whether the variant differs from the original bytes.
    var isProcessed: Bool {
        variant != original
    }

    /// The URL without its fragment and without the ignored query items. `data:` URLs are
    /// replaced by a digest of their content, so a large inline image is not used as a key.
    /// - Parameters:
    ///   - url: The URL.
    ///   - ignored: Query item names left out.
    private static func canonicalURL(_ url: URL, ignoring ignored: Set<String>) -> String {
        if url.scheme?.lowercased() == "data" {
            return "data:" + url.absoluteString.sha256Hex
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.fragment = nil
        if !ignored.isEmpty, let items = components.queryItems {
            let kept = items.filter { !ignored.contains($0.name) }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        return components.string ?? url.absoluteString
    }
}
