//
//  HLoggingSensitiveKeyAction.swift
//  Harbor
//
//  Created by Javier Manzo on 01/08/2026.
//

import Foundation

/// Describes an update to Harbor's sensitive-key redaction set, used by
/// ``Harbor/updateLogSensitiveKeys(_:)``. Harbor's logger inherits LogBird's
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
    /// Removes all configurable sensitive keys, disabling LogBird's key-based
    /// redaction of log metadata. Harbor's built-in HTTP credential keys still
    /// apply to headers, query values and bodies; use
    /// `Harbor.setLogSensitiveValues(true)` to inspect tokens or credentials.
    case clear
}
