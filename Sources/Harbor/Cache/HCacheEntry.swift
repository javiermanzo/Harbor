//
//  HCacheEntry.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import Foundation

// MARK: - Cache Entry Implementation

extension HCache.Manager {
    /// Cache entry wrapper containing data and timestamp for expiration checking.
    final class Entry: NSObject, Sendable {
        let data: Data
        let timestamp: Date

        init(data: Data, timestamp: Date) {
            self.data = data
            self.timestamp = timestamp
            super.init()
        }

        /// Checks if the cache entry is expired based on max age
        /// - Parameter maxAge: Maximum age in seconds. If nil, entry never expires
        /// - Returns: true if expired, false otherwise
        func isExpired(maxAge: TimeInterval?) -> Bool {
            guard let maxAge else { return false }
            return Date().timeIntervalSince(timestamp) > maxAge
        }
    }
}
