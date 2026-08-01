//
//  HConfig.swift
//
//
//  Created by Javier Manzo on 11/06/2024.
//

import Foundation
import LogBird

@HRequestManagerActor
struct HConfig: Sendable {
    /// Shared singleton instance of the configuration.
    static var shared = HConfig()

    /// Logger instance for configuration related events
    private static let logger = LogBird(subsystem: "com.harbor", category: "config")
    
    /// Authentication provider for adding credentials to requests.
    var authProvider: HAuthProviderProtocol?
    /// Default headers applied to all requests.
    var defaultHeaderParameters: [String: String]?
    /// mTLS identity for client certificate authentication.
    var mTLSIdentity: HMTLSIdentity?
    /// SSL pinning public key hashes for certificate validation.
    /// Malformed pins (not base64 SHA-256 hashes) log a warning when set and are ignored during validation.
    var sslPinningKeys: [String]? {
        didSet {
            guard let sslPinningKeys else { return }
            for key in sslPinningKeys where !HSPKI.isValidPin(key) {
                Self.logger.log("SSL pinning key \"\(key)\" is not a valid base64 SHA-256 hash and will never match. Pins must be base64(SHA256(SPKI)).", level: .warning)
            }
        }
    }
    /// Custom URLSession to use for all requests.
    var currentURLSession: URLSession?
    /// Whether mocks should only be enabled in DEBUG builds. Default is true.
    var mocksOnlyInDebug: Bool = true
    /// Whether logging is enabled for debug purposes. Default is false.
    var isLoggingEnabled: Bool = false
    /// Whether sensitive header values are printed in debug logs and generated cURL commands. Default is false (redacted).
    var logSensitiveHeaders: Bool = false
    /// Header names treated as sensitive (lowercased) and redacted from debug output unless `logSensitiveHeaders` is true.
    static let sensitiveHeaders: Set<String> = ["authorization", "cookie", "set-cookie", "x-api-key", "proxy-authorization"]
    /// Default cache type for requests without explicit cache settings. Default is `.urlCache`.
    var cacheType: HCache.CacheType = .urlCache()
    /// Default timeout interval for requests. Default is 15 seconds.
    var timeoutInterval: TimeInterval = 15

    /// Whether mocks are currently enabled based on build configuration and `mocksOnlyInDebug`.
    var mocksEnabled: Bool {
        #if DEBUG
        return true
        #else
        return !mocksOnlyInDebug
        #endif
    }
}
