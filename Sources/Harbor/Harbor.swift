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
        HRequestManager.authProvider = authProvider
    }

    public static func setDefaultHeaderParameters(_ headerParameters: [String: String]?) {
        HRequestManager.defaultHeaderParameters = headerParameters
    }
}
