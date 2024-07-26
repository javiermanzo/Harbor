//
//  PKCS12.swift
//
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation

final class PKCS12 {
    
    var label: String?
    var keyID: NSData?
    var trust: SecTrust?
    var certChain: [SecTrust]?
    var identity: SecIdentity?
    
    public init(p12Data: Data, password: String) {
        let importPasswordOption: NSDictionary = [kSecImportExportPassphrase as NSString: password]
        
        var items: CFArray?
        
        let status = SecPKCS12Import(p12Data as NSData, importPasswordOption, &items)
        
        guard status == errSecSuccess else {
            if status == errSecAuthFailed {
                NSLog("Incorrect password? ________")
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
