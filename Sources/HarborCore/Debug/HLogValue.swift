//
//  HLogValue.swift
//  HarborCore
//
//  Created by Javier Manzo on 16/11/2026.
//

import Foundation
import LogBird

/// A structured metadata value of a log entry.
package enum HLogValue: Sendable {
    /// A string.
    case string(String)
    /// An integer.
    case int(Int)
    /// A floating-point number.
    case double(Double)
    /// A Boolean.
    case bool(Bool)

    /// The LogBird value this one maps to.
    package var logBirdValue: LBValue {
        switch self {
        case .string(let value): return .string(value)
        case .int(let value): return .int(value)
        case .double(let value): return .double(value)
        case .bool(let value): return .bool(value)
        }
    }
}
