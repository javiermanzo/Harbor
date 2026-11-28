//
//  HImageDiskKey.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// The file name of a disk cache entry, built from SHA-256 digests so no key (a URL that may
/// carry a signed query, for example) is ever written as is. A processed variant is named after
/// its original (`<original digest>-<variant digest>`), so every variant of an image can be
/// found, and removed, with the original key alone.
struct HImageDiskKey: Sendable, Hashable {
    /// The file name.
    let fileName: String

    /// The key of the original bytes of an image.
    /// - Parameter originalKey: The original cache key (URL or `cacheKey`).
    static func original(_ originalKey: String) -> HImageDiskKey {
        HImageDiskKey(fileName: originalKey.sha256Hex)
    }

    /// The key of a processed variant of an image.
    /// - Parameters:
    ///   - variantKey: The variant cache key.
    ///   - originalKey: The original cache key it is rendered from.
    static func variant(_ variantKey: String, of originalKey: String) -> HImageDiskKey {
        HImageDiskKey(fileName: variantPrefix(of: originalKey) + variantKey.sha256Hex)
    }

    /// The beginning of the file names of every variant of an image.
    /// - Parameter originalKey: The original cache key.
    static func variantPrefix(of originalKey: String) -> String {
        originalKey.sha256Hex + "-"
    }
}

// MARK: - Cache Keys

extension HImageCacheKey {
    /// The disk key of the original bytes.
    var originalOnDisk: HImageDiskKey {
        .original(original)
    }

    /// The disk key of the processed variant.
    var variantOnDisk: HImageDiskKey {
        .variant(variant, of: original)
    }
}
