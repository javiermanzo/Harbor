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
        HRequestManager.config.authProvider = authProvider
    }
    
    /// Sets default headers applied to all requests.
    static func setDefaultHeaderParameters(_ defaultHeaderParameters: [String: String]?) {
        HRequestManager.config.defaultHeaderParameters = defaultHeaderParameters
    }
    
    /// Configures mutual TLS for client certificate authentication.
    static func setMTLS(_ mTLS: HmTLS?) {
        HRequestManager.config.mTLS = mTLS
    }
    
    /// Enables SSL pinning with SHA256 certificate hash.
    static func setSSlPinningSHA256(_ sslPinningSHA256: String?) {
        HRequestManager.config.sslPinningSHA256 = sslPinningSHA256
    }
    
    /// Sets custom URLSession for all Harbor requests.
    static func setCustomURLSession(_ customURLSession: URLSession) {
        HRequestManager.config.currentURLSession = customURLSession
    }
    
    /// Sets default cache configuration for requests without explicit cache settings.
    static func setDefaultCacheConfiguration(_ cacheConfiguration: HCache.Configuration) {
        HRequestManager.config.defaultCacheConfiguration = cacheConfiguration
    }
    
    /// Sets the default memory cache capacity (number of entries).
    static func setDefaultMemoryCacheCapacity(_ capacity: Int) {
        HRequestManager.config.defaultMemoryCacheCapacity = capacity
    }
    
    /// Sets the default disk cache capacity (number of entries).
    static func setDefaultDiskCacheCapacity(_ capacity: Int) {
        HRequestManager.config.defaultDiskCacheCapacity = capacity
    }
    
    /// Configures whether mocks are only active in DEBUG builds.
    static func setMocksOnlyInDebug(_ value: Bool) {
        HRequestManager.config.mocksOnlyInDebug = value
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
