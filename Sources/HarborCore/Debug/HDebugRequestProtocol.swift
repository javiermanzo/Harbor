//
//  HDebugRequestProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

/// Protocol for adding debug capabilities to network requests.
/// Implement this protocol to enable detailed logging of requests and responses.
///
/// Example usage:
/// ```swift
/// struct MyRequest: HGetRequestProtocol, HDebugRequestProtocol {
///     let debugType: HDebugRequestType = .requestAndResponse
///     // ... other properties
/// }
/// ```
public protocol HDebugRequestProtocol: Sendable {
    /// The type of debug information to log.
    var debugType: HDebugRequestType { get }
}

// MARK: - Default Implementation

/// Default implementation providing `.requestAndResponse` as the default debug type.
/// This ensures comprehensive logging by default while allowing customization.
public extension HDebugRequestProtocol {
    /// Default: `.requestAndResponse`.
    var debugType: HDebugRequestType { .requestAndResponse }
}
