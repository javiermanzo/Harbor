//
//  HPatchRequestProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - PATCH Request Protocol
/// Protocol for PATCH requests that partially update resources.
public protocol HPatchRequestProtocol: HRequestWithBodyProtocol {}

// MARK: - Default Implementations

/// Default implementations for `HPatchRequestProtocol`.
public extension HPatchRequestProtocol {
    /// The HTTP method for PATCH requests is `.patch`.
    var httpMethod: HHttpMethod { .patch }
}
