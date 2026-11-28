//
//  HImageCache.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// Namespace of HarborImage's cache settings: `HImageCache.Configuration`, set with
/// `HarborImage.setCacheConfiguration(_:)`, and `HImageCache.Scope`, used by
/// `HarborImage.clearCache(_:)`.
///
/// The memory cache holds decoded images, sized by their decoded bytes (`bytesPerRow × height`),
/// not by the size of their files; its entries do not expire. The disk cache holds the original
/// bytes and the processed variants in the app's `Caches` directory, expires them after
/// `expirationTime` and evicts the least recently used entries past its capacity.
///
/// Entries are keyed by URL (or `cacheKey`) and processing only: no credential, nor a digest of
/// one, is part of a key or of the files. They are shared by every account, so call
/// `HarborImage.clearCache()` whenever the signed-in account changes.
public enum HImageCache {}

// MARK: - Scope

public extension HImageCache {
    /// Which layers `HarborImage.clearCache(_:)` empties.
    enum Scope: String, Sendable, Hashable {
        /// The decoded images in memory.
        case memory
        /// The files on disk.
        case disk
        /// Both layers.
        case all
    }
}
