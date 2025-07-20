//
//  HCacheEntry.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import Foundation

// MARK: - Cache Entry Implementation

extension HCache.Manager {
    /// Cache entry wrapper containing data, timestamp, and expiration time.
    final class Entry: NSObject, Sendable {
        let data: Data
        let timestamp: Date
        let expirationTime: TimeInterval?

        init(data: Data, timestamp: Date, expirationTime: TimeInterval? = nil) {
            self.data = data
            self.timestamp = timestamp
            self.expirationTime = expirationTime
            super.init()
        }

        /// Checks if the cache entry is expired based on max age or stored expiration time
        /// - Parameter maxAge: Maximum age in seconds. If nil, uses stored expiration time
        /// - Returns: true if expired, false otherwise
        func isExpired(maxAge: TimeInterval?) -> Bool {
            let effectiveMaxAge = expirationTime ?? maxAge
            guard let maxAge = effectiveMaxAge else { return false }
            return Date().timeIntervalSince(timestamp) > maxAge
        }
    }
}
