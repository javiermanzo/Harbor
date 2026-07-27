//
//  Harbor.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import LogBird
import Security

/**
 Harbor - Protocol-oriented networking framework for Swift.

 Features: Caching, Authentication, SSL/TLS Security, Mocking, Async/Await, Retry Logic
 */
@HRequestManagerActor
public enum Harbor {

    /// Logger instance for configuration related events
    private static let logger = LogBird(subsystem: "com.harbor", category: "config")
}

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
    static func setMTLS(_ mTLS: HmTLS?) {
        HConfig.shared.mTLSIdentity = mTLS?.extractIdentity(loggingEnabled: HConfig.shared.isLoggingEnabled)
    }

    /// Enables SSL pinning with SHA256 hashes of the certificate's SubjectPublicKeyInfo (SPKI),
    /// base64 encoded. Provide multiple keys to support key rotation (backup pins).
    /// Use `Harbor.computePin(for:)` to generate pins from a certificate.
    static func setSSlPinningKeys(_ sslPinningKeys: [String]?) {
        if let sslPinningKeys {
            for key in sslPinningKeys where !HSPKI.isValidPin(key) {
                logger.log("SSL pinning key \"\(key)\" is not a valid base64 SHA-256 hash and will never match. Pins must be base64(SHA256(SPKI)).", level: .warning)
            }
        }
        HConfig.shared.sslPinningKeys = sslPinningKeys
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
        HConfig.shared.currentURLSession = customURLSession
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

    /// Configures whether sensitive header values (Authorization, Cookie, Set-Cookie, X-API-Key,
    /// Proxy-Authorization) are printed in debug logs and generated cURL commands.
    /// - Parameter enabled: If true, real values are printed. If false (default), values are redacted as `<redacted>`.
    static func setLogSensitiveHeaders(_ enabled: Bool) {
        HConfig.shared.logSensitiveHeaders = enabled
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

    /// Clears all cached data (memory and disk).
    static func clearAllCache() {
        HCache.Manager.shared.clearAllCache()
    }
}
