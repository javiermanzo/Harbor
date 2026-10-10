//
//  HDeleteRequestProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - DELETE Request Protocol
/// Protocol for DELETE requests that remove resources.
public protocol HDeleteRequestProtocol: HRequestWithEmptyResponseProtocol {}

// MARK: - Default Implementations

/// Default implementations for `HDeleteRequestProtocol`.
public extension HDeleteRequestProtocol {
    /// The HTTP method for DELETE requests is `.delete`.
    var httpMethod: HHttpMethod { .delete }
}
