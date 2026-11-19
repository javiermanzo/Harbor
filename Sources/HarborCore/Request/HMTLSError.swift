//
//  HMTLSError.swift
//  HarborCore
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation

/// Errors thrown when extracting a client identity from a P12 file.
public enum HMTLSError: Sendable {
    /// The P12 file does not exist or could not be read.
    case fileNotFound
    /// The password provider failed to supply a password.
    case passwordProviderFailed
    /// The P12 password is incorrect.
    case invalidPassword
    /// The P12 data is malformed or could not be imported.
    case invalidP12Format
    /// The P12 file was imported but contains no identity.
    case noIdentity
}

// MARK: - Error

extension HMTLSError: Error {}
