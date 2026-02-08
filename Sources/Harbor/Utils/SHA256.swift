//
//  SHA256.swift
//
//
//  Created by Javier Manzo on 26/07/2024.
//

import Foundation
import CryptoKit

final class SHA256 {
    static func sha256(data: Data) -> String {
        let digest = CryptoKit.SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
    }
    
    static func hash(data: Data) -> Data {
        let digest = CryptoKit.SHA256.hash(data: data)
        return Data(digest)
    }
}

// MARK: - String Extension for Cache Keys

extension String {
    var sha256Hash: String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
