//
//  PKCS12.swift
//
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation
import LogBird

/// Errors thrown when parsing a PKCS#12 archive.
enum PKCS12Error: Error, Equatable {
    /// `SecPKCS12Import` rejected the archive; carries the returned status
    /// (`errSecAuthFailed` for a wrong password, other codes for malformed data).
    case importFailed(OSStatus)
    /// The import reported success but the returned items are missing or malformed.
    case malformedContents
}

/// Helper class to extract client identity and certificates from a PKCS#12 archive.
struct PKCS12 {

    private static let logger = LogBird(subsystem: "com.harbor", category: "p12")

    /// The label of the imported item.
    let label: String?
    /// The key identifier.
    let keyID: Data?
    /// The trust management object.
    let trust: SecTrust?
    /// The certificate chain including intermediate certificates.
    let certChain: [SecCertificate]?
    /// The extracted client identity.
    let identity: SecIdentity?

    private init(label: String?, keyID: Data?, trust: SecTrust?, certChain: [SecCertificate]?, identity: SecIdentity?) {
        self.label = label
        self.keyID = keyID
        self.trust = trust
        self.certChain = certChain
        self.identity = identity
    }

    /// Parses the P12 data using the provided password.
    /// - Parameters:
    ///   - p12Data: The PKCS#12 archive data.
    ///   - password: The password to decrypt the archive.
    static func parse(p12Data: Data, password: String) throws(PKCS12Error) -> PKCS12 {
        let importPasswordOption: NSDictionary = [kSecImportExportPassphrase as NSString: password]

        var items: CFArray?

        let status = SecPKCS12Import(p12Data as NSData, importPasswordOption, &items)

        guard status == errSecSuccess else {
            #if DEBUG
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            Self.logger.log("PKCS12: import failed with status \(status): \(message)")
            #endif
            throw .importFailed(status)
        }

        guard let theItemsNSArray = items as NSArray?,
              let dictArray = theItemsNSArray as? [[String: AnyObject]] else {
            #if DEBUG
            Self.logger.log("PKCS12: error loading items")
            #endif
            throw .malformedContents
        }

        return PKCS12(label: getValue(by: kSecImportItemLabel, dictionaryArray: dictArray),
                      keyID: getValue(by: kSecImportItemKeyID, dictionaryArray: dictArray) as Data?,
                      trust: getValue(by: kSecImportItemTrust, dictionaryArray: dictArray),
                      certChain: getValue(by: kSecImportItemCertChain, dictionaryArray: dictArray),
                      identity: getValue(by: kSecImportItemIdentity, dictionaryArray: dictArray))
    }

    /// Extracts a specific value from the array of dictionaries returned by `SecPKCS12Import`.
    private static func getValue<T>(by key: CFString, dictionaryArray: [[String: AnyObject]]) -> T? {
        for dictionary in dictionaryArray {
            if let value = dictionary[key as String] as? T {
                return value
            }
        }

        return nil
    }
}
