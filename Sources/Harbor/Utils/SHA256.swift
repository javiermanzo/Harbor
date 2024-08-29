//
//  SHA256.swift
//
//
//  Created by Javier Manzo on 26/07/2024.
//

import Foundation
import CommonCrypto

final class SHA256 {
    static func sha256(data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).base64EncodedString()
    }
}
