//
//  Harbor.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

public final class Harbor {

    private init() {}

    public static func setAuthProvider(_ authProvider: HAuthProviderProtocol?) {
        HRequestManager.config.authProvider = authProvider
    }

    public static func setDefaultHeaderParameters(_ defaultHeaderParameters: [String: String]?) {
        HRequestManager.config.defaultHeaderParameters = defaultHeaderParameters
    }

    public static func setMTLS(_ mTLS: HmTLS?) {
        HRequestManager.config.mTLS = mTLS
    }

    public static func setSSlPinningSHA256(_ sslPinningSHA256: String?) {
        HRequestManager.config.sslPinningSHA256 = sslPinningSHA256
    }
}
