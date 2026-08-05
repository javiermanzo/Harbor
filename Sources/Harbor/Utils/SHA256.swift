//
//  SHA256.swift
//
//
//  Created by Javier Manzo on 26/07/2024.
//

import Foundation
import CryptoKit

final class SHA256 {
    /// Returns the SHA-256 digest of the data, base64 encoded. Used for SSL pinning pins.
    static func sha256Base64(data: Data) -> String {
        let digest = CryptoKit.SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
    }

    /// Returns the raw SHA-256 digest bytes of the data.
    static func sha256Data(data: Data) -> Data {
        let digest = CryptoKit.SHA256.hash(data: data)
        return Data(digest)
    }

    @available(*, deprecated, renamed: "sha256Base64(data:)")
    static func sha256(data: Data) -> String {
        sha256Base64(data: data)
    }

    @available(*, deprecated, renamed: "sha256Data(data:)")
    static func hash(data: Data) -> Data {
        sha256Data(data: data)
    }
}

// MARK: - String Extension for Cache Keys

extension String {
    /// Lowercase hex-encoded SHA-256 digest of the string's UTF-8 bytes. Used for cache keys.
    var sha256Hex: String {
        let data = Data(self.utf8)
        let hash = SHA256.sha256Data(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    @available(*, deprecated, renamed: "sha256Hex")
    var sha256Hash: String {
        sha256Hex
    }
}
