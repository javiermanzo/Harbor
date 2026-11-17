//
//  SHA256.swift
//
//
//  Created by Javier Manzo on 26/07/2024.
//

import Foundation
import CryptoKit

/// SHA-256 hashing utilities for SSL pinning and cache key generation.
enum SHA256 {
    /// Returns the SHA-256 digest of the data, base64 encoded. Used for SSL pinning pins.
    /// - Parameter data: The data to hash.
    /// - Returns: Base64-encoded string representation of the SHA-256 digest.
    static func sha256Base64(data: Data) -> String {
        let digest = CryptoKit.SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
    }

    /// Returns the raw SHA-256 digest bytes of the data.
    /// - Parameter data: The data to hash.
    /// - Returns: Raw bytes of the SHA-256 digest.
    static func sha256Data(data: Data) -> Data {
        let digest = CryptoKit.SHA256.hash(data: data)
        return Data(digest)
    }
}

// MARK: - String Extension for Cache Keys

/// SHA-256 helpers for cache keys.
extension String {
    /// Lowercase hex-encoded SHA-256 digest of the string's UTF-8 bytes. Used for cache keys.
    package var sha256Hex: String {
        let digits = Array("0123456789abcdef")
        var hex = ""
        hex.reserveCapacity(64)
        for byte in SHA256.sha256Data(data: Data(self.utf8)) {
            hex.append(digits[Int(byte >> 4)])
            hex.append(digits[Int(byte & 0x0f)])
        }
        return hex
    }
}
