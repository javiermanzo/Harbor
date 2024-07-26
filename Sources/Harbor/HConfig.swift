//
//  HConfig.swift
//
//
//  Created by Javier Manzo on 11/06/2024.
//

import Foundation

public struct HConfig {
    let authProvider: HAuthProviderProtocol?
    let defaultHeaderParameters: [String: String]?
    let mTLS: HmTLS?
    let sslPinningSHA256: String?

    public init(authProvider: HAuthProviderProtocol? = nil, 
                defaultHeaderParameters: [String : String]? = nil,
                mTLS: HmTLS? = nil,
                sslPinningSHA256: String? = nil) {
        self.authProvider = authProvider
        self.defaultHeaderParameters = defaultHeaderParameters
        self.mTLS = mTLS
        self.sslPinningSHA256 = sslPinningSHA256
    }
}
