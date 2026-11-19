//
//  HLogLevel.swift
//  HarborCore
//
//  Created by Javier Manzo on 16/11/2026.
//

import Foundation
import LogBird

/// Severity of a log entry.
package enum HLogLevel: Sendable {
    /// Verbose diagnostics (requests, responses, messages).
    case debug
    /// A noteworthy event.
    case info
    /// A recoverable problem.
    case warning
    /// A failure.
    case error

    /// The LogBird level this one maps to.
    package var logBirdLevel: LBLogLevel {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }
}
