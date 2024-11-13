//
//  Harbor.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

@HRequestManagerActor
public final class Harbor: Sendable {

    private init() {}

    /// Configures the authentication provider for network requests.
    /// - Parameter authProvider: An optional object conforming to `HAuthProviderProtocol` to handle authentication.
    public static func setAuthProvider(_ authProvider: HAuthProviderProtocol?) {
        HRequestManager.config.authProvider = authProvider
    }

    /// Sets default HTTP header parameters for all requests.
    /// - Parameter defaultHeaderParameters: A dictionary of header field names and values.
    public static func setDefaultHeaderParameters(_ defaultHeaderParameters: [String: String]?) {
        HRequestManager.config.defaultHeaderParameters = defaultHeaderParameters
    }

    /// Configures mutual TLS (mTLS) settings.
    /// - Parameter mTLS: An optional `HmTLS` object containing mTLS configuration.
    public static func setMTLS(_ mTLS: HmTLS?) {
        HRequestManager.config.mTLS = mTLS
    }

    /// Enables SSL pinning using SHA256 hash.
    /// - Parameter sslPinningSHA256: An optional string representing the SHA256 hash for SSL pinning.
    public static func setSSlPinningSHA256(_ sslPinningSHA256: String?) {
        HRequestManager.config.sslPinningSHA256 = sslPinningSHA256
    }

    /// Sets a custom URL session for network requests.
    /// - Parameter customURLSession: A `URLSession` instance to be used for requests.
    public static func setCustomURLSession(_ customURLSession: URLSession) {
        HRequestManager.config.currentURLSession = customURLSession
    }

    /// Registers a mock object for your requests.
    /// - Parameter mock: An `HMock` object to be registered.
    public static func register(mock: HMock) {
        HMocker.register(mock: mock)
    }

    /// Removes a specific mock.
    /// - Parameter mock: An `HMock` object to be removed.
    public static func remove(mock: HMock) {
        HMocker.remove(mock: mock)
    }

    /// Removes all registered mocks.
    public static func removeAllMocks() {
        HMocker.removeAll()
    }

    /// Configures whether mocks should be used only in DEBUG mode.
    /// - Parameter value: A boolean indicating if mocks are restricted to debug mode.
    public static func setMocksOnlyInDebug(_ value: Bool) {
        HRequestManager.config.mocksOnlyInDebug = value
    }
}
