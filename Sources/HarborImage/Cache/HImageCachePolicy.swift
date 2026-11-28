//
//  HImageCachePolicy.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// Whether a load reads the cache before downloading.
public enum HImageCachePolicy: String, Sendable, Hashable {
    /// Serve the image from memory (which does not expire) or from a disk entry that has not
    /// expired (an expired one while offline or when the download fails transiently), and
    /// download otherwise (default).
    case useCache
    /// Download even when the image is cached, then replace the cached copy (pull-to-refresh).
    /// Offline it fails with `.noConnection`, even when the image is cached.
    case reloadIgnoringCache
    /// Serve the cached image, even an expired one, and never download: fails with `.notCached`.
    case returnCacheDontLoad
}
