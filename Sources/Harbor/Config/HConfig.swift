//
//  HConfig.swift
//
//
//  Created by Javier Manzo on 11/06/2024.
//

import Foundation

@HRequestManagerActor
struct HConfig: Sendable {
    /// Shared singleton instance of the configuration.
    static var shared = HConfig()
    
    /// Authentication provider for adding credentials to requests.
    var authProvider: HAuthProviderProtocol?
    /// Default headers applied to all requests.
    var defaultHeaderParameters: [String: String]?
    /// mTLS identity for client certificate authentication.
    var mTLSIdentity: HMTLSIdentity?
    /// SSL pinning public key hashes for certificate validation.
    var sslPinningKeys: [String]?
    /// Custom URLSession to use for all requests.
    var currentURLSession: URLSession?
    /// Whether mocks should only be enabled in DEBUG builds. Default is true.
    var mocksOnlyInDebug: Bool = true
    /// Whether logging is enabled for debug purposes. Default is false.
    var isLoggingEnabled: Bool = false
    /// Default cache type for requests without explicit cache settings. Default is `.urlCache`.
    var defaultCacheType: HCache.CacheType = .urlCache()

    /// Whether mocks are currently enabled based on build configuration and `mocksOnlyInDebug`.
    var mocksEnabled: Bool {
        #if DEBUG
        return true
        #else
        return !mocksOnlyInDebug
        #endif
    }
}
