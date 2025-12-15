//
//  HmTLS.swift
//
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation
@preconcurrency import Security

/// A Sendable wrapper for SecIdentity
public struct HMTLSIdentity: Sendable {
    public let identity: SecIdentity
    
    public init(identity: SecIdentity) {
        self.identity = identity
    }
}

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
    
    func extractIdentity() -> HMTLSIdentity? {
        do {
            let p12Data = try Data(contentsOf: p12FileUrl)
            let p12Contents = PKCS12(p12Data: p12Data, password: password)

            if let identity = p12Contents.identity {
                return HMTLSIdentity(identity: identity)
            } else {
                print("Harbor: Failed to extract identity from P12")
                return nil
            }
        } catch {
            print("Harbor: Failed to read P12 file: \(error)")
            return nil
        }
    }
}
