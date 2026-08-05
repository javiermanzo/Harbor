//
//  HSPKI.swift
//
//
//  Created by Javier Manzo on 27/07/2026.
//

import Foundation
import Security

/// Utilities to compute SSL pinning hashes over a certificate's SubjectPublicKeyInfo (SPKI).
///
/// The pin format is `base64(SHA256(SPKI))`, the same produced by:
/// `openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64`
enum HSPKI {

    /// ASN.1 headers that, prepended to the raw public key bytes returned by
    /// `SecKeyCopyExternalRepresentation`, rebuild the full SubjectPublicKeyInfo DER structure.
    /// This is the same approach used by TrustKit.
    private static let rsa2048SPKIHeader: [UInt8] = [
        0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
        0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
    ]

    private static let rsa4096SPKIHeader: [UInt8] = [
        0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
        0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00
    ]

    private static let ecdsaSecp256r1SPKIHeader: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
        0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
        0x42, 0x00
    ]

    private static let ecdsaSecp384r1SPKIHeader: [UInt8] = [
        0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
        0x01, 0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00
    ]

    /// Returns the SubjectPublicKeyInfo DER bytes for a certificate's public key,
    /// or `nil` if the key cannot be extracted or its type/size is unsupported.
    static func spkiData(for certificate: SecCertificate) -> Data? {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return nil
        }

        guard let attributes = SecKeyCopyAttributes(publicKey) as? [String: Any],
              let keyType = attributes[kSecAttrKeyType as String] as? String,
              let keySize = attributes[kSecAttrKeySizeInBits as String] as? Int else {
            return nil
        }

        let rsaKeyType = kSecAttrKeyTypeRSA as String
        let ecKeyType = kSecAttrKeyTypeECSECPrimeRandom as String
        let ecLegacyKeyType = kSecAttrKeyTypeEC as String

        let spkiHeader: [UInt8]
        switch (keyType, keySize) {
        case (rsaKeyType, 2048):
            spkiHeader = rsa2048SPKIHeader
        case (rsaKeyType, 4096):
            spkiHeader = rsa4096SPKIHeader
        case (ecKeyType, 256), (ecLegacyKeyType, 256):
            spkiHeader = ecdsaSecp256r1SPKIHeader
        case (ecKeyType, 384), (ecLegacyKeyType, 384):
            spkiHeader = ecdsaSecp384r1SPKIHeader
        default:
            return nil
        }

        return Data(spkiHeader) + publicKeyData
    }

    /// Computes the SSL pin for a certificate: `base64(SHA256(SPKI))`.
    /// - Returns: The pin string, or `nil` if the certificate's key type is unsupported.
    static func pin(for certificate: SecCertificate) -> String? {
        guard let spkiData = spkiData(for: certificate) else {
            return nil
        }
        return SHA256.sha256Base64(data: spkiData)
    }

    /// Validates that a pin string is base64 decoding to exactly 32 bytes (SHA-256),
    /// with (44 chars) or without (43 chars) padding.
    static func isValidPin(_ pin: String) -> Bool {
        var base64 = pin
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64) else {
            return false
        }
        return data.count == 32
    }

    /// Normalizes a pin for comparison, making padding optional.
    static func normalizePin(_ pin: String) -> String {
        pin.trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}
