//
//  HConfig.swift
//
//
//  Created by Javier Manzo on 11/06/2024.
//

import Foundation

open class HConfig {
    public let authProvider: HAuthProviderProtocol?
    public let defaultHeaderParameters: [String: String]?
    public let mTLS: HmTLS?
    public let sslPinningSHA256: String?

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
