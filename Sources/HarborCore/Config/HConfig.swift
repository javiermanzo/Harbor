//
//  HConfig.swift
//
//
//  Created by Javier Manzo on 11/06/2024.
//

import Foundation

/// Configuration shared by every Harbor product (auth, security, timeouts, logging, the
/// custom session). REST-only settings live in `HRESTConfig` and WebSocket ones in
/// `HWebSocketConfig`. Access is serialized via `@HRequestManagerActor` to ensure thread safety.
@HRequestManagerActor
package struct HConfig: Sendable {
    /// Shared singleton instance of the configuration.
    package static var shared = HConfig()

    /// Authentication provider for adding credentials to requests.
    package var authProvider: HAuthProviderProtocol?
    /// Default headers applied to all requests.
    package var defaultHeaderParameters: [String: String]?
    /// mTLS identity for client certificate authentication.
    var mTLSIdentity: HMTLSIdentity? {
        didSet { securityGeneration &+= 1 }
    }
    /// Incremented by every `Harbor.setMTLS(_:)` and `Harbor.clearMTLS()` call, so an import
    /// that finishes after a later call does not overwrite it (the latest call wins).
    var mTLSGeneration = 0
    /// Incremented whenever pins or the mTLS identity change. `HURLSessionDelegate` records it
    /// at creation, so a custom session holding an outdated delegate can be detected.
    var securityGeneration = 0
    /// SSL pinning public key hashes for certificate validation.
    /// Malformed pins (not base64 SHA-256 hashes) log a warning when set and are ignored during validation.
    var sslPinningKeys: [String]? {
        didSet {
            securityGeneration &+= 1
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
            securityGeneration &+= 1
            if let sslPinningKeysByHost {
                for keys in sslPinningKeysByHost.values {
                    Self.validatePins(keys)
                }
            }
        }
    }
    /// Custom URLSession provided by the user to use for all requests. Used as-is when set:
    /// Harbor's SSL pinning, mTLS and redirect policies only apply when its delegate is
    /// `HURLSessionDelegate` (see `Harbor.makeURLSessionDelegate()`) or forwards to one.
    package var customURLSession: URLSession?
    /// Whether debug logging is enabled. Default is true in DEBUG builds, false in RELEASE builds.
    var isLoggingEnabled: Bool = HBuild.isDebug
    /// Whether sensitive values (headers, query values, body fields, error bodies) are printed
    /// unredacted in debug logs, generated cURL commands and `HRequestError` descriptions.
    /// Default is false (redacted). Backed by `HRedactionPolicy` so nonisolated code
    /// (e.g. `HRequestError.errorDescription`) reads the same value.
    var logSensitiveValues: Bool {
        get { HRedactionPolicy.logsSensitiveValues }
        set { HRedactionPolicy.logsSensitiveValues = newValue }
    }
    /// Default timeout interval for requests. Default is 15 seconds. Applied to every
    /// `URLRequest` (`timeoutInterval`) unless the request overrides it, so it also holds
    /// for custom sessions. It bounds the idle time between packets, not the whole transfer.
    package var timeoutInterval: TimeInterval = 15
    /// Maximum time a whole transfer may take (`URLSessionConfiguration.timeoutIntervalForResource`)
    /// in sessions Harbor builds. `nil` (default) keeps the system default of 7 days.
    var resourceTimeoutInterval: TimeInterval?
    /// Whether DEBUG/simulator builds assume network availability instead of trusting the
    /// connectivity monitor. Default is true; set to false to exercise `.noConnection` flows in debug.
    var assumeNetworkAvailableInDebug: Bool = true
    /// Whether URLRequests handle cookies through the shared cookie storage. Default is false.
    package var httpShouldHandleCookies: Bool = false
    /// URLProtocol classes injected into internally built sessions, allowing networking
    /// to be stubbed per session instead of registering protocols globally.
    var protocolClasses: [AnyClass]?

    /// Logs a security warning (visible even with debug logging disabled) for an empty pin
    /// list, which rejects every connection it applies to, and for every pin that is not a
    /// valid base64 SHA-256 hash.
    private static func validatePins(_ keys: [String]) {
        if keys.isEmpty {
            HLogger.securityWarning("An empty SSL pinning key list rejects every TLS connection it applies to. Pass nil to disable pinning.")
        }
        for key in keys where !HSPKI.isValidPin(key) {
            HLogger.securityWarning("SSL pinning key \"\(key)\" is not a valid base64 SHA-256 hash and will never match. Pins must be base64(SHA256(SPKI)).")
        }
    }
}
