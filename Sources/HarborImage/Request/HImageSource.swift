//
//  HImageSource.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// Where a loaded image came from.
public enum HImageSource: String, Sendable, Hashable {
    /// The decoded image was in the memory cache.
    case memory
    /// The image was read from the disk cache.
    case disk
    /// The image was downloaded.
    case network
    /// The image came from a `data:` or `file:` URL, or from a mock in debug builds.
    case local
}
