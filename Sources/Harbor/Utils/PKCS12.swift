//
//  PKCS12.swift
//
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation
import LogBird

final class PKCS12 {

    private static let logger = LogBird(subsystem: "com.harbor", category: "p12")

    var label: String?
    var keyID: NSData?
    var trust: SecTrust?
    var certChain: [SecCertificate]?
    var identity: SecIdentity?
    /// Status returned by `SecPKCS12Import`; `errSecSuccess` when the import succeeded.
    private(set) var importStatus: OSStatus
    var loggingEnabled: Bool

    init(p12Data: Data, password: String, loggingEnabled: Bool = false) {
        self.loggingEnabled = loggingEnabled
        let importPasswordOption: NSDictionary = [kSecImportExportPassphrase as NSString: password]

        var items: CFArray?

        let status = SecPKCS12Import(p12Data as NSData, importPasswordOption, &items)
        self.importStatus = status

        guard status == errSecSuccess else {
            if status == errSecAuthFailed {
                #if DEBUG
                if loggingEnabled {
                    Self.logger.log("PKCS12: Incorrect password")
                }
                #endif
            }
            return
        }

        guard let theItemsCFArray = items else {
            #if DEBUG
            if loggingEnabled {
                Self.logger.log("PKCS12: error loading items")
            }
            #endif
            return
        }
        
        let theItemsNSArray: NSArray = theItemsCFArray as NSArray

        guard let dictArray = theItemsNSArray as? [[String: AnyObject]] else {
            #if DEBUG
            if loggingEnabled {
                Self.logger.log("PKCS12: error loading items")
            }
            #endif
            return
        }

        label = getValue(by: kSecImportItemLabel, dictionaryArray: dictArray)
        keyID = getValue(by: kSecImportItemKeyID, dictionaryArray: dictArray)
        trust = getValue(by: kSecImportItemTrust, dictionaryArray: dictArray)
        certChain = getValue(by: kSecImportItemCertChain, dictionaryArray: dictArray)
        identity = getValue(by: kSecImportItemIdentity, dictionaryArray: dictArray)
    }

    private func getValue<T>(by key: CFString, dictionaryArray: [[String: AnyObject]]) -> T? {
        for dictionary in dictionaryArray {
            if let value = dictionary[key as String] as? T {
                return value
            }
        }

        return nil
    }
}
