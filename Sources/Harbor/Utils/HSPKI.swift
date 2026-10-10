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

    /// DER `AlgorithmIdentifier` for `rsaEncryption` (OID 1.2.840.113549.1.1.1) with NULL parameters.
    private static let rsaAlgorithmIdentifier: [UInt8] = [
        0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00
    ]

    /// DER `AlgorithmIdentifier` for `id-ecPublicKey` (OID 1.2.840.10045.2.1) on secp256r1 (OID 1.2.840.10045.3.1.7).
    private static let ecdsaSecp256r1AlgorithmIdentifier: [UInt8] = [
        0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07
    ]

    /// DER `AlgorithmIdentifier` for `id-ecPublicKey` on secp384r1 (OID 1.3.132.0.34).
    private static let ecdsaSecp384r1AlgorithmIdentifier: [UInt8] = [
        0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22
    ]

    /// DER `AlgorithmIdentifier` for `id-ecPublicKey` on secp521r1 (OID 1.3.132.0.35).
    private static let ecdsaSecp521r1AlgorithmIdentifier: [UInt8] = [
        0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x23
    ]

    /// Returns the SubjectPublicKeyInfo DER bytes for a certificate's public key.
    /// - Parameter certificate: The certificate to extract SPKI bytes from.
    /// - Returns: SubjectPublicKeyInfo DER bytes, or `nil` if the key cannot be extracted or its type/size is unsupported.
    static func spkiData(for certificate: SecCertificate) -> Data? {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }
        return spkiData(for: publicKey)
    }

    /// Returns the SubjectPublicKeyInfo DER bytes for a public key:
    /// `SEQUENCE { AlgorithmIdentifier, BIT STRING { key } }`, where the key is the raw
    /// representation returned by `SecKeyCopyExternalRepresentation` (PKCS#1 `RSAPublicKey`
    /// for RSA, the uncompressed X9.63 point for EC). This is the structure TrustKit
    /// rebuilds with fixed headers; the lengths are encoded here so any RSA key size works.
    ///
    /// Supported keys: RSA of any size and EC on P-256, P-384 and P-521.
    /// - Parameter publicKey: The public key.
    /// - Returns: SubjectPublicKeyInfo DER bytes, or `nil` if the key cannot be exported or its type/size is unsupported.
    static func spkiData(for publicKey: SecKey) -> Data? {
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

        let algorithmIdentifier: [UInt8]
        switch (keyType, keySize) {
        case (rsaKeyType, _):
            algorithmIdentifier = rsaAlgorithmIdentifier
        case (ecKeyType, 256), (ecLegacyKeyType, 256):
            algorithmIdentifier = ecdsaSecp256r1AlgorithmIdentifier
        case (ecKeyType, 384), (ecLegacyKeyType, 384):
            algorithmIdentifier = ecdsaSecp384r1AlgorithmIdentifier
        case (ecKeyType, 521), (ecLegacyKeyType, 521):
            algorithmIdentifier = ecdsaSecp521r1AlgorithmIdentifier
        default:
            return nil
        }

        // BIT STRING with zero unused bits wrapping the raw key.
        let bitString = derElement(tag: 0x03, content: [0x00] + [UInt8](publicKeyData))
        return Data(derElement(tag: 0x30, content: algorithmIdentifier + bitString))
    }

    /// Encodes a DER element: tag, definite length (short or long form) and content.
    /// - Parameters:
    ///   - tag: The ASN.1 tag byte.
    ///   - content: The element content.
    /// - Returns: The encoded element.
    static func derElement(tag: UInt8, content: [UInt8]) -> [UInt8] {
        return [tag] + derLength(content.count) + content
    }

    /// Encodes a DER definite length.
    /// - Parameter length: The content length in bytes.
    /// - Returns: The short form for lengths below 128, the long form otherwise.
    static func derLength(_ length: Int) -> [UInt8] {
        guard length >= 0x80 else {
            return [UInt8(length)]
        }
        var bytes: [UInt8] = []
        var remaining = length
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xff), at: 0)
            remaining >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    /// Computes the SSL pin for a certificate: `base64(SHA256(SPKI))`.
    /// - Parameter certificate: The certificate to generate the pin for.
    /// - Returns: The pin string, or `nil` if the certificate's key type is unsupported.
    static func pin(for certificate: SecCertificate) -> String? {
        guard let spkiData = spkiData(for: certificate) else {
            return nil
        }
        return SHA256.sha256Base64(data: spkiData)
    }

    /// Validates that a pin string is base64 decoding to exactly 32 bytes (SHA-256),
    /// with (44 chars) or without (43 chars) padding.
    /// - Parameter pin: The base64 pin string to validate.
    /// - Returns: `true` if the pin is a valid SHA-256 base64 string, `false` otherwise.
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

    /// Normalizes a pin for comparison by stripping trailing `=` padding characters.
    /// - Parameter pin: The raw pin string.
    /// - Returns: The normalized pin string without trailing `=` padding.
    static func normalizePin(_ pin: String) -> String {
        pin.trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}
