//
//  PKCS12.swift
//
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation
import LogBird

final class PKCS12 {
    
    private static let logger = LogBird(subsystem: "com.harbor", category: "security")

    var label: String?
    var keyID: NSData?
    var trust: SecTrust?
    var certChain: [SecTrust]?
    var identity: SecIdentity?
    
    init(p12Data: Data, password: Data) {
        let importPasswordOption: NSDictionary = [kSecImportExportPassphrase as String: password]
        
        var items: CFArray?
        
        let status = SecPKCS12Import(p12Data as NSData, importPasswordOption, &items)
        
        guard status == errSecSuccess else {
            if status == errSecAuthFailed {
                Self.logger.log("PKCS12: Incorrect password")
            }
            return
        }
        
        guard let theItemsCFArray = items else { return }
        let theItemsNSArray: NSArray = theItemsCFArray as NSArray
        
        guard let dictArray = theItemsNSArray as? [[String: AnyObject]] else {
            return
        }
        
        func getValue<T>(by key: CFString) -> T? {
            for dict in dictArray {
                if let value = dict[key as String] as? T {
                    return value
                }
            }
            
            return nil
        }
        
        label = getValue(by: kSecImportItemLabel)
        keyID = getValue(by: kSecImportItemKeyID)
        trust = getValue(by: kSecImportItemTrust)
        certChain = getValue(by: kSecImportItemCertChain)
        identity = getValue(by: kSecImportItemIdentity)
    }
}
