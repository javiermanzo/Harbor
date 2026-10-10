//
//  HPostRequestProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - POST Request Protocol
/// Protocol for POST requests that create new resources.
public protocol HPostRequestProtocol: HRequestWithBodyProtocol {}

// MARK: - Default Implementations

/// Default implementations for `HPostRequestProtocol`.
public extension HPostRequestProtocol {
    /// The HTTP method for POST requests is `.post`.
    var httpMethod: HHttpMethod { .post }
}
