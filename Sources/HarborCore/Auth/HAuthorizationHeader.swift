//
//  HAuthorizationHeader.swift
//  HarborCore
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

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

// MARK: - Hashable

extension HAuthorizationHeader: Hashable {}
