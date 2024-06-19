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

    public init(authProvider: HAuthProviderProtocol? = nil, 
                defaultHeaderParameters: [String : String]? = nil,
                mTLS: HmTLS? = nil) {
        self.authProvider = authProvider
        self.defaultHeaderParameters = defaultHeaderParameters
        self.mTLS = mTLS
    }
}
