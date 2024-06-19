//
//  HmTLS.swift
//
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation

public struct HmTLS {
    let p12FileUrl: URL
    let password: String

    public init(p12FileUrl: URL, password: String) {
        self.p12FileUrl = p12FileUrl
        self.password = password
    }
}
