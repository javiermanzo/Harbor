//
//  Harbor.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

public final class Harbor {

    private init() {}
    
    public static func setAuthProvider(_ authProvider: HAuthProviderProtocol) {
        HServiceManager.authProvider = authProvider
    }

    public static func setDefaultHeaderParameters(_ headerParameters: [String: String]?) {
        HServiceManager.defaultHeaderParameters = headerParameters
    }
}
