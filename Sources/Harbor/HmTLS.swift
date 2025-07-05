//
//  HmTLS.swift
//
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation

/// Configuration for mutual TLS (mTLS) authentication.
/// Use this to configure client certificates for secure communication.
public struct HmTLS: Sendable {
    /// The URL to the P12 certificate file.
    let p12FileUrl: URL
    /// The password for the P12 certificate file.
    let password: String

    /// Creates a new mTLS configuration.
    /// - Parameters:
    ///   - p12FileUrl: The URL to the P12 certificate file
    ///   - password: The password for the P12 certificate file
    public init(p12FileUrl: URL, password: String) {
        self.p12FileUrl = p12FileUrl
        self.password = password
    }
}
