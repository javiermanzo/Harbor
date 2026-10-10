//
//  HPutRequestProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - PUT Request Protocol
/// Protocol for PUT requests that update existing resources.
public protocol HPutRequestProtocol: HRequestWithBodyProtocol {}

// MARK: - Default Implementations

/// Default implementations for `HPutRequestProtocol`.
public extension HPutRequestProtocol {
    /// The HTTP method for PUT requests is `.put`.
    var httpMethod: HHttpMethod { .put }
}
