//
//  HLoggingSensitiveKeyAction.swift
//  Harbor
//
//  Created by Javier Manzo on 01/08/2026.
//

import Foundation

/// Describes an update to Harbor's sensitive-key redaction set, used by
/// ``Harbor/loggingSensitiveKeys(_:)``. Harbor's logger inherits LogBird's
/// global default sensitive keys; these actions let you override, extend,
/// restore or disable them for Harbor's logger.
public enum HLoggingSensitiveKeyAction: Sendable {
    /// Replaces the full sensitive-key set. LogBird's defaults are not merged
    /// back in.
    case set([String])
    /// Appends keys to the current set, ignoring duplicates.
    case add([String])
    /// Restores LogBird's default sensitive-key set.
    case reset
    /// Removes all sensitive keys, disabling redaction. Useful when debugging
    /// and you need to inspect tokens or credentials.
    case clear
}
