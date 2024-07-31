//
//  HJRPCConfig.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

public class HJRPCConfig: HConfig {
    public let url: String
    public let jrpcVersion: String

    public init(url: String, jrpcVersion: String = "2.0", authProvider: HAuthProviderProtocol? = nil,
                defaultHeaderParameters: [String : String]? = nil,
                mTLS: HmTLS? = nil,
                sslPinningSHA256: String? = nil) {
        self.url = url
        self.jrpcVersion = jrpcVersion
        super.init(authProvider: authProvider, defaultHeaderParameters: defaultHeaderParameters, mTLS: mTLS, sslPinningSHA256: sslPinningSHA256)
    }
}
