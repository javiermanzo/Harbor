//
//  ServerCertificateFetcher.swift
//  HarborExample
//
//  Support for the SSL pinning demo
//

import Foundation

/// Fetches a host's leaf certificate by opening a TLS connection, so a pin can be
/// computed from the live certificate with `Harbor.computePin(for:)`.
/// Trust evaluation is left to the default handling; the certificate is only observed.
final class ServerCertificateFetcher: NSObject, URLSessionDelegate, @unchecked Sendable {
    /// Returns the leaf certificate presented by the given host.
    /// - Throws: `URLError.badURL` when the host is invalid, or
    ///   `URLError.serverCertificateUntrusted` when no certificate could be read.
    static func fetchCertificate(from host: String) async throws -> SecCertificate {
        guard let url = URL(string: "https://\(host)/") else {
            throw URLError(.badURL)
        }

        let fetcher = ServerCertificateFetcher()
        let session = URLSession(configuration: .ephemeral, delegate: fetcher, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        // The response itself is not needed; the TLS handshake delivers the certificate.
        _ = try? await session.data(from: url)

        guard let certificate = fetcher.serverCertificate else {
            throw URLError(.serverCertificateUntrusted)
        }
        return certificate
    }

    /// Guards `serverCertificateStorage`, which is written on the session's delegate queue
    /// and read after the data task completes.
    private let lock = NSLock()
    nonisolated(unsafe) private var serverCertificateStorage: SecCertificate?

    private var serverCertificate: SecCertificate? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return serverCertificateStorage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            serverCertificateStorage = newValue
        }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] {
            serverCertificate = chain.first
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
