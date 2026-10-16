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
    ///
    /// Harbor calls it at most once per request, and always once when a request that needs
    /// auth fails with `.authNeeded` after a `401`. When the header returned by
    /// `getAuthorizationHeader()` already differs from the rejected one (a refresh completed
    /// meanwhile, or the provider issues a new header on every call), the request is first
    /// retried with it without calling this method; `authFailed()` is only called if that
    /// retry is rejected too. Concurrent requests rejected with the same authorization header
    /// share a single call: they await the in-flight one instead of calling it again.
    func authFailed() async
}

/// Represents an authorization header with a key-value pair.
/// Used by authentication providers to specify header information.
public struct HAuthorizationHeader: Sendable {
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

// MARK: - Equatable, Hashable

extension HAuthorizationHeader: Equatable, Hashable {}
