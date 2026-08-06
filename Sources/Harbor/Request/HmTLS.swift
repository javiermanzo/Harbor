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
    /// The password provider failed to supply a password.
    case passwordProviderFailed
    /// The P12 password is incorrect.
    case invalidPassword
    /// The P12 data is malformed or could not be imported.
    case invalidP12Format
    /// The P12 file was imported but contains no identity.
    case noIdentity
}

/// A Sendable wrapper for SecIdentity.
///
/// `SecIdentity` and `SecCertificate` are CoreFoundation reference types: they are
/// reference-counted, immutable after creation and safe to read from any thread, so
/// passing this wrapper across concurrency domains never shares mutable state. The
/// `@preconcurrency import Security` above accounts for the Security framework not
/// yet annotating these types as `Sendable`.
public struct HMTLSIdentity: Sendable {
    /// The core client identity.
    public let identity: SecIdentity
    /// Certificate chain extracted from the P12 file (including intermediates), sent alongside the identity.
    public let certificateChain: [SecCertificate]?

    /// Creates a new identity wrapper.
    /// - Parameters:
    ///   - identity: The client identity.
    ///   - certificateChain: The associated certificate chain, if any.
    public init(identity: SecIdentity, certificateChain: [SecCertificate]? = nil) {
        self.identity = identity
        self.certificateChain = certificateChain
    }
}

/// Configuration for mutual TLS (mTLS) authentication.
/// Use this to configure client certificates for secure communication.
public struct HMTLS: Sendable {
    /// The URL to the P12 certificate file.
    let p12FileUrl: URL
    /// Supplies the P12 password on demand. It is called once when the identity is
    /// extracted and the returned password is not retained, so the password is not
    /// kept alive for the lifetime of this value. The async signature accommodates
    /// password sources that are themselves asynchronous, such as keychain wrappers,
    /// biometric prompts or remote vaults.
    let passwordProvider: @Sendable () async throws -> String

    /// Creates a new mTLS configuration.
    /// - Parameters:
    ///   - p12FileUrl: The URL to the P12 certificate file.
    ///   - passwordProvider: A closure that returns the password for the P12 certificate file.
    public init(p12FileUrl: URL, passwordProvider: @escaping @Sendable () async throws -> String) {
        self.p12FileUrl = p12FileUrl
        self.passwordProvider = passwordProvider
    }

    /// Creates a new mTLS configuration with a fixed password.
    /// - Parameters:
    ///   - p12FileUrl: The URL to the P12 certificate file.
    ///   - password: The password for the P12 certificate file.
    @available(*, deprecated, message: "Use init(p12FileUrl:passwordProvider:) instead; it requests the password once when the identity is extracted instead of retaining it.")
    public init(p12FileUrl: URL, password: String) {
        self.init(p12FileUrl: p12FileUrl, passwordProvider: { password })
    }

    /// Extracts the client identity from the P12 file.
    /// - Throws: `HMTLSError.fileNotFound` when the file cannot be read, `.passwordProviderFailed`
    ///   when the password provider throws, `.invalidPassword` when the password is rejected,
    ///   `.invalidP12Format` when the import fails for any other reason, or `.noIdentity`
    ///   when the file holds no identity.
    func extractIdentity() async throws(HMTLSError) -> HMTLSIdentity {
        guard let p12Data = try? Data(contentsOf: p12FileUrl) else {
            throw HMTLSError.fileNotFound
        }

        let password: String
        do {
            password = try await passwordProvider()
        } catch {
            throw HMTLSError.passwordProviderFailed
        }

        let p12Contents: PKCS12
        do {
            p12Contents = try PKCS12.parse(p12Data: p12Data, password: password)
        } catch let pkcsError {
            switch pkcsError {
            case .importFailed(let status):
                throw status == errSecAuthFailed ? HMTLSError.invalidPassword : HMTLSError.invalidP12Format
            case .malformedContents:
                throw HMTLSError.invalidP12Format
            }
        }

        guard let identity = p12Contents.identity else {
            throw HMTLSError.noIdentity
        }

        return HMTLSIdentity(identity: identity, certificateChain: p12Contents.certChain)
    }
}

extension HMTLS: CustomStringConvertible {
    /// Redacted description; the password is never included.
    public var description: String {
        "HMTLS(p12: \(p12FileUrl.lastPathComponent), password: <redacted>)"
    }
}

@available(*, deprecated, renamed: "HMTLS", message: "Use HMTLS with init(p12FileUrl:passwordProvider:) so the password is requested on demand instead of being retained.")
public typealias HmTLS = HMTLS
