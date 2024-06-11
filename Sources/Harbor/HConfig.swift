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

    init(authProvider: HAuthProviderProtocol? = nil, defaultHeaderParameters: [String : String]? = nil) {
        self.authProvider = authProvider
        self.defaultHeaderParameters = defaultHeaderParameters
    }
}
