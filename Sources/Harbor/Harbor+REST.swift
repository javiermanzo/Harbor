//
//  Harbor+REST.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import HarborCore

// MARK: - REST Configuration

public extension Harbor {

    /// Sets default cache type for requests without explicit cache settings.
    /// Default is .urlCache.
    ///
    /// The memory limit of the custom cache follows the default configuration when it is
    /// `.custom`; per-request configurations can only raise it, never lower it.
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    /// - Parameter cacheType: The cache type applied to GET requests whose `cacheType` is `nil`.
    static func setDefaultCacheType(_ cacheType: HCache.CacheType) {
        HRESTConfig.shared.cacheType = cacheType
        HCache.Manager.shared.applyDefaultCacheType(cacheType)
    }

    /// Whether registered mocks currently answer requests.
    ///
    /// Default: `true` in DEBUG builds and `false` otherwise. Change it with `setMocksEnabled(_:)`.
    static var mocksEnabled: Bool {
        HRESTConfig.shared.mocksEnabled
    }

    /// Turns mocks on or off. While mocks are off, registered mocks are kept but ignored and
    /// every request reaches the network.
    ///
    /// By default mocks are on in DEBUG builds and off in release builds, so a mock left
    /// registered by mistake never answers in production. Call `setMocksEnabled(true)` to use
    /// them in a release build (e.g. a UI-test or demo configuration).
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    /// - Parameter enabled: Whether registered mocks answer requests.
    static func setMocksEnabled(_ enabled: Bool) {
        HRESTConfig.shared.mocksEnabled = enabled
    }
}

// MARK: - Mocking

public extension Harbor {

    /// Registers a mock that answers every request of `mock.request` while mocks are enabled
    /// (see `setMocksEnabled(_:)`). Any mock or mock sequence already registered for that
    /// request type is replaced.
    /// - Parameter mock: The response to answer requests of `mock.request` with.
    static func register(mock: HMock) {
        HMocker.register(mock: mock)
    }

    /// Registers a scripted sequence of mock responses for a request type. Each attempt of a
    /// request of that type (retries included) resolves to the next response in order; the last
    /// one repeats thereafter. Any mock or mock sequence already registered for that request
    /// type is replaced. A sequence with no responses is ignored.
    /// - Parameter mockSequence: The responses to play back for requests of `mockSequence.request`.
    static func register(mockSequence: HMockSequence) {
        HMocker.register(mockSequence: mockSequence)
    }

    /// Removes the mock or mock sequence registered for a request type, so its requests reach
    /// the network again.
    /// - Parameter requestType: The request type that stops being mocked.
    static func removeMock(for requestType: HRequestBaseRequestProtocol.Type) {
        HMocker.removeMock(for: requestType)
    }

    /// Removes every registered mock and mock sequence, and resets the mock call counts.
    static func removeAllMocks() {
        HMocker.removeAll()
    }

    /// The number of times requests of the given type have been answered by a mock. Every
    /// attempt counts, so a request retried twice adds 3.
    /// - Parameter requestType: The request type whose mock resolutions are counted.
    /// - Returns: The number of mocked attempts since launch or the last `removeAllMocks()`.
    static func mockCallCount(for requestType: HRequestBaseRequestProtocol.Type) -> Int {
        HMocker.callCount(for: requestType)
    }

    /// Whether a mock or mock sequence is currently registered for the request type.
    /// - Parameter requestType: The request type to look up.
    /// - Returns: `true` when requests of that type are answered by a mock while mocks are enabled.
    static func isMockRegistered(for requestType: HRequestBaseRequestProtocol.Type) -> Bool {
        HMocker.isRegistered(requestType)
    }
}

// MARK: - Cache Management

public extension Harbor {

    /// Clears all cached data: the custom cache (memory and disk), `URLCache.shared`, and the
    /// URLCache of the configured default cache type and custom session when they differ.
    /// The credentials remembered for offline cache lookups are forgotten as well.
    static func clearAllCache() async {
        HRequestManager.forgetRememberedAuthHeaders()
        await HCache.Manager.shared.clearAllCache()
        URLCache.shared.removeAllCachedResponses()

        if case .urlCache(let cache, _) = HRESTConfig.shared.cacheType, cache !== URLCache.shared {
            cache.removeAllCachedResponses()
        }

        if let sessionCache = HConfig.shared.customURLSession?.configuration.urlCache, sessionCache !== URLCache.shared {
            sessionCache.removeAllCachedResponses()
        }
    }
}
