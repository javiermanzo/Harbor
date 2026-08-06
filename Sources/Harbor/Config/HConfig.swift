//
//  HConfig.swift
//
//
//  Created by Javier Manzo on 11/06/2024.
//

import Foundation
import LogBird

/// Internal configuration state for Harbor.
///
/// This struct holds all the global configuration options used by the library.
/// Access is serialized via `@HRequestManagerActor` to ensure thread safety.
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
            if let sslPinningKeys {
                Self.validatePins(sslPinningKeys)
            }
        }
    }
    /// SSL pinning public key hashes scoped to specific hosts. When a host is present here,
    /// its pins take precedence over the global `sslPinningKeys`; challenges from hosts
    /// absent from this map fall back to the global pins or, when none are set, to default handling.
    /// Host keys are normalized (lowercased, without a trailing root-label dot) when stored
    /// and when looked up, matching how DNS names are resolved. Malformed pins (not base64
    /// SHA-256 hashes) log a warning when set and are ignored during validation.
    var sslPinningKeysByHost: [String: [String]]? {
        didSet {
            if let sslPinningKeysByHost {
                for keys in sslPinningKeysByHost.values {
                    Self.validatePins(keys)
                }
            }
        }
    }
    /// Custom URLSession provided by the user to use for all requests. Used as-is when set.
    var customURLSession: URLSession?
    /// Whether mocks should only be enabled in DEBUG builds. Default is true.
    var mocksOnlyInDebug: Bool = true
    /// Explicit override for `mocksEnabled`. When non-nil it takes precedence over the
    /// DEBUG/`mocksOnlyInDebug` computation, letting tests (or release builds) force mocks on/off.
    var mocksEnabledOverride: Bool?
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
    /// Whether DEBUG/simulator builds assume network availability instead of trusting the
    /// connectivity monitor. Default is true; set to false to exercise `.noConnection` flows in debug.
    var assumeNetworkAvailableInDebug: Bool = true
    /// Whether URLRequests handle cookies through the shared cookie storage. Default is false.
    var httpShouldHandleCookies: Bool = false
    /// URLProtocol classes injected into internally built sessions, allowing networking
    /// to be stubbed per session instead of registering protocols globally.
    var protocolClasses: [AnyClass]?

    /// Whether mocks are currently enabled based on build configuration and `mocksOnlyInDebug`.
    /// An explicit override (`mocksEnabledOverride`) takes precedence over the build rule.
    var mocksEnabled: Bool {
        if let override = mocksEnabledOverride {
            return override
        }
        #if DEBUG
        return true
        #else
        return !mocksOnlyInDebug
        #endif
    }

    /// Logs a warning for every pin that is not a valid base64 SHA-256 hash.
    private static func validatePins(_ keys: [String]) {
        for key in keys where !HSPKI.isValidPin(key) {
            Self.logger.log("SSL pinning key \"\(key)\" is not a valid base64 SHA-256 hash and will never match. Pins must be base64(SHA256(SPKI)).", level: .warning)
        }
    }
}
