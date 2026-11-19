//
//  HDebugRequestType.swift
//  HarborCore
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

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
