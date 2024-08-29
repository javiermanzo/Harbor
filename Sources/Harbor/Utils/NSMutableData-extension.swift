//
//  NSMutableData.swift
//  
//
//  Created by Javier Manzo on 11/06/2024.
//

import Foundation

internal extension NSMutableData {
    func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.append(data)
        }
    }
}
