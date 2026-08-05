//
//  HmTLS.swift
//
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation
@preconcurrency import Security

/// Errors thrown when extracting a client identity from a P12 file.
public enum HMTLSError: Error, Sendable {
    /// The P12 file does not exist or could not be read.
    case fileNotFound
    /// The P12 password is incorrect.
    case invalidPassword
    /// The P12 data is malformed or could not be imported.
    case invalidP12Format
    /// The P12 file was imported but contains no identity.
    case noIdentity
}

/// A Sendable wrapper for SecIdentity
public struct HMTLSIdentity: Sendable {
    public let identity: SecIdentity
    /// Certificate chain extracted from the P12 file (including intermediates), sent alongside the identity.
    public let certificateChain: [SecCertificate]?

    public init(identity: SecIdentity, certificateChain: [SecCertificate]? = nil) {
        self.identity = identity
        self.certificateChain = certificateChain
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
    
    /// Extracts the client identity from the P12 file.
    /// - Throws: `HMTLSError.fileNotFound` when the file cannot be read, `.invalidPassword`
    ///   when the password is rejected, `.invalidP12Format` when the import fails for any
    ///   other reason, or `.noIdentity` when the file holds no identity.
    func extractIdentity(loggingEnabled: Bool = false) throws(HMTLSError) -> HMTLSIdentity {
        guard let p12Data = try? Data(contentsOf: p12FileUrl) else {
            throw HMTLSError.fileNotFound
        }

        let p12Contents = PKCS12(p12Data: p12Data, password: password, loggingEnabled: loggingEnabled)

        guard p12Contents.importStatus == errSecSuccess else {
            throw p12Contents.importStatus == errSecAuthFailed ? HMTLSError.invalidPassword : HMTLSError.invalidP12Format
        }

        guard let identity = p12Contents.identity else {
            throw HMTLSError.noIdentity
        }

        return HMTLSIdentity(identity: identity, certificateChain: p12Contents.certChain)
    }
}
