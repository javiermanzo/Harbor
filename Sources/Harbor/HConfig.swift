//
//  HConfig.swift
//
//
//  Created by Javier Manzo on 11/06/2024.
//

import Foundation

@HRequestManagerActor
struct HConfig: Sendable {
    var authProvider: HAuthProviderProtocol?
    var defaultHeaderParameters: [String: String]?
    var mTLS: HmTLS?
    var sslPinningSHA256: String?
    var currentURLSession: URLSession?
    var mocksOnlyInDebug: Bool = true

    var mocksEnabled: Bool {
        #if DEBUG
        return true
        #else
        return !mocksOnlyInDebug
        #endif
    }
}
