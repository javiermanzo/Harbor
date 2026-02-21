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
    var mTLSIdentity: HMTLSIdentity?
    var sslPinningKeys: [String]?
    var currentURLSession: URLSession?
    var mocksOnlyInDebug: Bool = true
    var isLoggingEnabled: Bool = false
    var defaultCachePolicy: HCache.Policy = .urlCache()

    var mocksEnabled: Bool {
        #if DEBUG
        return true
        #else
        return !mocksOnlyInDebug
        #endif
    }
}
