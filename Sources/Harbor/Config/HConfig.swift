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
    var sslPinningKeys: [String]?
    var currentURLSession: URLSession?
    var mocksOnlyInDebug: Bool = true
    var defaultCacheConfiguration: HCache.Configuration = .enabled(expirationTime: .oneWeek)
    var defaultMemoryCacheCapacity: Int = 100
    var defaultStartUpMemoryCacheCapacity: Int = 50

    var mocksEnabled: Bool {
        #if DEBUG
        return true
        #else
        return !mocksOnlyInDebug
        #endif
    }
}
