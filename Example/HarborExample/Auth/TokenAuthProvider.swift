//
//  TokenAuthProvider.swift
//  HarborExample
//
//  Token-based authentication provider for the "GET - With Auth" demo
//

import Foundation
import Harbor
import LogBird

/// Token-based authentication provider.
///
/// An `actor`, so the token can be set from the UI while Harbor reads it from its own actor
/// without a data race. It returns `nil` (the request is sent without an authorization
/// header) when no token was set or the token has expired.
actor TokenAuthProvider {
    private var accessToken: String?
    private var tokenExpiration: Date?

    private static let logger = LogBird(subsystem: "com.harbor.example", category: "Auth")
}

// MARK: - Token

extension TokenAuthProvider {
    func setToken(_ token: String, expiresIn: TimeInterval) {
        accessToken = token
        tokenExpiration = Date().addingTimeInterval(expiresIn)
    }
}

// MARK: - HAuthProviderProtocol

extension TokenAuthProvider: HAuthProviderProtocol {
    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        guard let token = accessToken, let expiration = tokenExpiration, expiration > Date() else {
            return nil
        }
        return HAuthorizationHeader(key: "Authorization", value: "Bearer \(token)")
    }

    func authFailed() async {
        // Handle auth failure - e.g., refresh token or show login
        Self.logger.log("Authentication failed!", level: .error)
    }
}
