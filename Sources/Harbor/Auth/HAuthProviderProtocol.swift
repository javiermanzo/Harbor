//
//  HAuthProviderProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

/// Protocol for providing authentication headers to network requests.
/// Implement this protocol to provide custom authentication logic.
public protocol HAuthProviderProtocol: Sendable {
    /// Returns the authorization header for the current request.
    /// - Returns: An `HAuthorizationHeader` containing the key-value pair for authorization,
    ///   or `nil` when no credentials are available. In that case the request is sent
    ///   without an authorization header.
    func getAuthorizationHeader() async -> HAuthorizationHeader?

    /// Called when authentication fails, allowing the provider to handle the failure.
    /// This method can be used to refresh tokens, show login screens, etc.
    func authFailed() async
}

/// Represents an authorization header with a key-value pair.
/// Used by authentication providers to specify header information.
public struct HAuthorizationHeader: Sendable, Equatable, Hashable {
    /// The header field name (e.g., "Authorization", "X-API-Key").
    public let key: String

    /// The header field value (e.g., "Bearer token123", "api-key-value").
    public let value: String

    /// Creates a new authorization header.
    /// - Parameters:
    ///   - key: The header field name
    ///   - value: The header field value
    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}
