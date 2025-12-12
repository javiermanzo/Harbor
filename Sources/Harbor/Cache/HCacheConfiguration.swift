//
//  HCacheConfiguration.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import Foundation

public extension HCache {
    /// Configuration for request caching behavior.
    enum Configuration: Sendable {
        /// Caching is disabled for this request.
        case disabled
        /// Caching is enabled with optional custom expiration time and max object size in MB (default 10MB).
        case enabled(expirationTime: TimeInterval? = .oneWeek, maxObjectSizeInMBs: Int = 10)

        /// Whether caching is enabled for this configuration.
        var isEnabled: Bool {
            switch self {
            case .disabled:
                return false
            case .enabled:
                return true
            }
        }

        /// Gets the expiration time, nil means use default in cache manager.
        var expirationTime: TimeInterval? {
            switch self {
            case .disabled:
                return nil
            case .enabled(let expirationTime, _):
                return expirationTime
            }
        }

        /// Gets the max object size in bytes. Returns 0 if disabled.
        var maxObjectSizeInBytes: Int {
            switch self {
            case .disabled:
                return 0
            case .enabled(_, let maxObjectSizeInMBs):
                return maxObjectSizeInMBs * 1024 * 1024
            }
        }
    }
}
