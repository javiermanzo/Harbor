//
//  HMTLSIdentity.swift
//  HarborCore
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation
@preconcurrency import Security

/// A client identity extracted from a PKCS#12 file, with the certificate chain and the hosts
/// it is presented to. Built from an `HMTLS` configuration by `Harbor.setMTLS(_:)`.
///
/// `SecIdentity` and `SecCertificate` are CoreFoundation reference types: they are
/// reference-counted, immutable after creation and safe to read from any thread, so
/// passing this wrapper across concurrency domains never shares mutable state. The
/// `@preconcurrency import Security` above accounts for the Security framework not
/// yet annotating these types as `Sendable`.
struct HMTLSIdentity: Sendable {
    /// The core client identity.
    let identity: SecIdentity
    /// Certificate chain extracted from the P12 file (including intermediates), sent alongside the identity.
    let certificateChain: [SecCertificate]?
    /// Hosts the identity is presented to, normalized (lowercased, without a trailing
    /// root-label dot). `nil` presents it to every host that requests a client certificate.
    let hosts: Set<String>?

    /// Creates a new identity wrapper.
    /// - Parameters:
    ///   - identity: The client identity.
    ///   - certificateChain: The associated certificate chain, if any.
    ///   - hosts: The hosts the identity is presented to, or `nil` (default) for every host.
    init(identity: SecIdentity, certificateChain: [SecCertificate]? = nil, hosts: Set<String>? = nil) {
        self.identity = identity
        self.certificateChain = certificateChain
        self.hosts = hosts.map { Set($0.map(HURLSessionDelegate.normalizedHost)) }
    }

    /// Whether the identity may be presented to the given host.
    /// - Parameter host: The host requesting a client certificate.
    func applies(toHost host: String) -> Bool {
        guard let hosts else { return true }
        return hosts.contains(HURLSessionDelegate.normalizedHost(host))
    }
}
