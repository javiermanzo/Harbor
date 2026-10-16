//
//  HDebugRequestProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - Debug Protocol

/// Protocol for adding debug capabilities to network requests.
/// Implement this protocol to enable detailed logging of requests and responses.
///
/// Example usage:
/// ```swift
/// struct MyRequest: HGetRequestProtocol, HDebugRequestProtocol {
///     var debugType: HDebugRequestType = .requestAndResponse
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

// MARK: - Debug Type

/// Specifies the type of debug information to log for network requests.
public enum HDebugRequestType: Sendable {
    /// No debug information is logged.
    case none
    /// Only request information is logged.
    case request
    /// Only response information is logged.
    case response
    /// Both request and response information is logged.
    case requestAndResponse
}
