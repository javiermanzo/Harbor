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
    /// Custom URLSession provided by the user to use for all requests. Used as-is when set.
    var customURLSession: URLSession?
    /// Whether mocks should only be enabled in DEBUG builds. Default is true.
    var mocksOnlyInDebug: Bool = true
    /// Whether debug logging is enabled. Default is true in DEBUG builds, false in RELEASE builds.
    #if DEBUG
    var isLoggingEnabled: Bool = true
    #else
    var isLoggingEnabled: Bool = false
    #endif
    /// Whether sensitive header values are printed in debug logs and generated cURL commands. Default is false (redacted).
    var logSensitiveHeaders: Bool = false
    /// Header names treated as sensitive (lowercased) and redacted from debug output unless `logSensitiveHeaders` is true.
    static let sensitiveHeaders: Set<String> = ["authorization", "cookie", "set-cookie", "x-api-key", "proxy-authorization"]
    /// Default cache type for requests without explicit cache settings. Default is `.urlCache`.
    var cacheType: HCache.CacheType = .urlCache()
    /// Default timeout interval for requests. Default is 15 seconds.
    var timeoutInterval: TimeInterval = 15
    /// Backoff and jitter defaults used to build the effective retry policy of requests that
    /// only specify `retries`. The number of attempts always comes from the request itself.
    var defaultRetryPolicy: HRetryPolicy = HRetryPolicy()
    /// Whether DEBUG/simulator builds assume network availability instead of trusting the
    /// connectivity monitor. Default is true; set to false to exercise `.noConnection` flows in debug.
    var assumeNetworkAvailableInDebug: Bool = true
    /// URLProtocol classes injected into internally built sessions, allowing networking
    /// to be stubbed per session instead of registering protocols globally.
    var protocolClasses: [AnyClass]?

    /// Whether mocks are currently enabled based on build configuration and `mocksOnlyInDebug`.
    var mocksEnabled: Bool {
        #if DEBUG
        return true
        #else
        return !mocksOnlyInDebug
        #endif
    }
}
