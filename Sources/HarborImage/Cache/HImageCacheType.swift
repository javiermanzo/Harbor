//
//  HImageCacheType.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// Where an image is cached. Set the default with `HarborImage.setDefaultCacheType(_:)` and
/// override it per request with `HImageRequestProtocol.cacheType`.
public enum HImageCacheType: String, Sendable, Hashable {
    /// Decoded images in memory and their bytes on disk (default).
    case memoryAndDisk
    /// Decoded images in memory only; nothing is written to disk. For private images that
    /// must not outlive the process.
    case memoryOnly
    /// Bytes on disk only; the decoded image is not kept in memory.
    case diskOnly
    /// No caching: every load downloads and decodes the image.
    case disabled
}

// MARK: - Layers

extension HImageCacheType {
    /// Whether decoded images are kept in memory.
    var usesMemory: Bool {
        self == .memoryAndDisk || self == .memoryOnly
    }

    /// Whether bytes are kept on disk.
    var usesDisk: Bool {
        self == .memoryAndDisk || self == .diskOnly
    }
}
