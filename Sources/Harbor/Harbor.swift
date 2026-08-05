//
//  Harbor.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import Security

/**
 Harbor - Protocol-oriented networking framework for Swift.

 Features: Caching, Authentication, SSL/TLS Security, Mocking, Async/Await, Retry Logic
 */
@HRequestManagerActor
public enum Harbor {}

// MARK: - Configuration

public extension Harbor {

    /// Configures authentication provider for requests requiring auth.
    static func setAuthProvider(_ authProvider: HAuthProviderProtocol?) {
        HConfig.shared.authProvider = authProvider
    }

    /// Sets default headers applied to all requests.
    static func setDefaultHeaderParameters(_ defaultHeaderParameters: [String: String]?) {
        HConfig.shared.defaultHeaderParameters = defaultHeaderParameters
    }

    /// Configures mutual TLS for client certificate authentication.
    /// - Parameter mTLS: The mTLS configuration.
    /// - Throws: `HMTLSError` when the identity could not be extracted from the P12
    ///   (file missing, wrong password, malformed, no identity). mTLS stays disabled in that case.
    static func setMTLS(_ mTLS: HmTLS) throws {
        do {
            HConfig.shared.mTLSIdentity = try mTLS.extractIdentity(loggingEnabled: HConfig.shared.isLoggingEnabled)
            HRequestManager.invalidateURLSession()
        } catch {
            HConfig.shared.mTLSIdentity = nil
            HRequestManager.invalidateURLSession()
            HLogger.log("mTLS identity could not be configured", error: error, level: .error)
            throw error
        }
    }

    /// Disables mutual TLS by clearing any configured client identity.
    static func clearMTLS() {
        HConfig.shared.mTLSIdentity = nil
        HRequestManager.invalidateURLSession()
    }

    /// Enables SSL pinning with SHA256 hashes of the certificate's SubjectPublicKeyInfo (SPKI),
    /// base64 encoded. Provide multiple keys to support key rotation (backup pins).
    /// Use `Harbor.computePin(for:)` to generate pins from a certificate.
    static func setSSlPinningKeys(_ sslPinningKeys: [String]?) {
        HConfig.shared.sslPinningKeys = sslPinningKeys
        HRequestManager.invalidateURLSession()
    }

    /// Computes the SSL pin for a certificate: `base64(SHA256(SPKI))`.
    /// This matches the output of:
    /// `openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64`
    /// - Parameter certificate: The certificate to pin.
    /// - Returns: The pin string, or `nil` if the certificate's key type is unsupported.
    static func computePin(for certificate: SecCertificate) -> String? {
        HSPKI.pin(for: certificate)
    }

    /// Sets custom URLSession for all Harbor requests.
    static func setCustomURLSession(_ customURLSession: URLSession) {
        HConfig.shared.customURLSession = customURLSession
    }

    /// Sets default cache type for requests without explicit cache settings.
    /// Default is .urlCache.
    static func setDefaultCacheType(_ cacheType: HCache.CacheType) {
        HConfig.shared.cacheType = cacheType
    }

    /// Sets default timeout interval for requests.
    /// Default is 15 seconds.
    static func setDefaultTimeoutInterval(_ timeout: TimeInterval) {
        HConfig.shared.timeoutInterval = timeout
        HRequestManager.invalidateURLSession()
    }

    /// Sets URLProtocol classes for internally built sessions.
    static func setProtocolClasses(_ protocolClasses: [AnyClass]?) {
        HConfig.shared.protocolClasses = protocolClasses
        HRequestManager.invalidateURLSession()
    }

    /// Configures whether mocks are only active in DEBUG builds.
    static func setMocksOnlyInDebug(_ value: Bool) {
        HConfig.shared.mocksOnlyInDebug = value
    }

    /// Configures whether debug logs are enabled.
    /// - Parameter enabled: If true, logs will be printed (subject to #if DEBUG). If false, no logs will be printed.
    static func setLoggingEnabled(_ enabled: Bool) {
        HConfig.shared.isLoggingEnabled = enabled
    }

    /// Configures sensitive-key redaction for debug logs.
    ///
    /// A key is sensitive when it contains any of the configured values;
    /// matching is case-insensitive and ignores separators, so `accessToken`,
    /// `access-token` and `ACCESS_TOKEN` all match `token`.
    ///
    /// Harbor starts from LogBird's global defaults, which already cover
    /// common HTTP auth fields (`authorization`, `auth`, `cookie`, `apikey`,
    /// `bearer`, `credentials`, `token`, `password`, `secret`, `privatekey`).
    ///
    /// Examples:
    /// ```swift
    /// await Harbor.loggingSensitiveKeys(.set(["signature", "otp"])) // replace the full set
    /// await Harbor.loggingSensitiveKeys(.add(["signature"]))          // extend the current set
    /// await Harbor.loggingSensitiveKeys(.reset)                       // restore the defaults
    /// await Harbor.loggingSensitiveKeys(.clear)                       // disable redaction (debug)
    /// ```
    ///
    /// - Parameter action: The update to apply to the sensitive-key set.
    static func loggingSensitiveKeys(_ action: HLoggingSensitiveKeyAction) {
        HLogger.sensitiveKeys(action)
    }

    /// Configures whether sensitive header values (Authorization, Cookie, Set-Cookie, X-API-Key,
    /// Proxy-Authorization) and sensitive fields in JSON response bodies (e.g. `access_token`,
    /// `refresh_token`) are printed in debug logs and generated cURL commands.
    /// - Parameter enabled: If true, real values are printed. If false (default), values are redacted as `<redacted>`.
    static func setLogSensitiveHeaders(_ enabled: Bool) {
        HConfig.shared.logSensitiveHeaders = enabled
    }

    /// Configures whether DEBUG/simulator builds assume network availability instead of
    /// trusting the connectivity monitor. Default is true; set to false to exercise
    /// `.noConnection` flows in debug builds.
    static func setAssumeNetworkAvailableInDebug(_ value: Bool) {
        HConfig.shared.assumeNetworkAvailableInDebug = value
    }
}

// MARK: - Network Monitoring

public extension Harbor {

    /// Stops the internal network connectivity monitor and resets its state.
    /// The monitor restarts lazily on the next connectivity check. Useful for tests and resets.
    static func stopNetworkMonitor() {
        HRequestManager.connectivityMonitor.stop()
    }
}

// MARK: - Mocking

public extension Harbor {

    /// Registers a mock response for testing.
    static func register(mock: HMock) {
        HMocker.register(mock: mock)
    }

    /// Removes a specific mock.
    static func remove(mock: HMock) {
        HMocker.remove(mock: mock)
    }

    /// Removes all registered mocks.
    static func removeAllMocks() {
        HMocker.removeAll()
    }
}

// MARK: - Cache Management

public extension Harbor {

    /// Clears all cached data: the custom cache (memory and disk), `URLCache.shared`, and the
    /// URLCache of the configured default cache type and custom session when they differ.
    static func clearAllCache() async {
        await HCache.Manager.shared.clearAllCache()
        URLCache.shared.removeAllCachedResponses()

        if case .urlCache(let cache, _) = HConfig.shared.cacheType, cache !== URLCache.shared {
            cache.removeAllCachedResponses()
        }

        if let sessionCache = HConfig.shared.customURLSession?.configuration.urlCache, sessionCache !== URLCache.shared {
            sessionCache.removeAllCachedResponses()
        }
    }
}
