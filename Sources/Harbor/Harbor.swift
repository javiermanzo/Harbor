//
//  Harbor.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

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
    static func setMTLS(_ mTLS: HmTLS?) {
        HConfig.shared.mTLSIdentity = mTLS?.extractIdentity(loggingEnabled: HConfig.shared.isLoggingEnabled)
    }

    /// Enables SSL pinning with SHA256 public key hashes.
    /// Provide multiple keys to support key rotation (backup pins).
    static func setSSlPinningKeys(_ sslPinningKeys: [String]?) {
        HConfig.shared.sslPinningKeys = sslPinningKeys
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
