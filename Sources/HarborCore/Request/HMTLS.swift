//
//  HMTLS.swift
//  HarborCore
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation
@preconcurrency import Security

/// Configuration for mutual TLS (mTLS) authentication: the client certificate (a PKCS#12
/// file) Harbor presents when a server requests one. Apply it with `Harbor.setMTLS(_:)`.
///
/// ```swift
/// let mTLS = HMTLS(p12FileUrl: certURL, hosts: ["api.example.com"]) { try await keychain.p12Password() }
/// try await Harbor.setMTLS(mTLS)
/// ```
public struct HMTLS: Sendable {
    /// The URL to the P12 certificate file.
    let p12FileUrl: URL
    /// Supplies the P12 password on demand. It is called once when the identity is
    /// extracted and the returned password is not retained, so the password is not
    /// kept alive for the lifetime of this value. The async signature accommodates
    /// password sources that are themselves asynchronous, such as keychain wrappers,
    /// biometric prompts or remote vaults.
    let passwordProvider: @Sendable () async throws -> String
    /// Hosts the client identity is presented to, normalized (lowercased, without a trailing
    /// root-label dot). `nil` presents it to every host that requests a client certificate;
    /// other hosts get default handling (no certificate).
    let hosts: Set<String>?

    /// Creates a new mTLS configuration.
    /// - Parameters:
    ///   - p12FileUrl: The URL to the P12 certificate file.
    ///   - hosts: The hosts the client identity is presented to (matched against
    ///     `URLProtectionSpace.host`, case-insensitively). Default `nil` presents it to every
    ///     host that requests a client certificate. Scoping it is recommended so the identity
    ///     is never offered to unexpected servers.
    ///   - passwordProvider: A closure that returns the password for the P12 certificate file.
    public init(p12FileUrl: URL, hosts: Set<String>? = nil, passwordProvider: @escaping @Sendable () async throws -> String) {
        self.p12FileUrl = p12FileUrl
        self.hosts = hosts.map { Set($0.map(HURLSessionDelegate.normalizedHost)) }
        self.passwordProvider = passwordProvider
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

        return HMTLSIdentity(identity: identity, certificateChain: p12Contents.certChain, hosts: hosts)
    }
}

// MARK: - CustomStringConvertible

extension HMTLS: CustomStringConvertible {
    /// Redacted description; the password is never included.
    public var description: String {
        let scope = hosts.map { $0.sorted().joined(separator: ", ") } ?? "all"
        return "HMTLS(p12: \(p12FileUrl.lastPathComponent), hosts: \(scope), password: <redacted>)"
    }
}
