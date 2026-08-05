//
//  HURLSessionDelegate.swift
//
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation
import LogBird
import Security

final class HURLSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {

    typealias HChallengeResult = (disposition: URLSession.AuthChallengeDisposition, credential: URLCredential?)

    /// Logger instance for SSL/TLS related events
    private static let logger = LogBird(subsystem: "com.harbor", category: "ssl")

    private let mTLSIdentity: HMTLSIdentity?
    private let sslPinningKeys: [String]?
    private let sslPinningKeysByHost: [String: [String]]?

    init(mTLSIdentity: HMTLSIdentity?, sslPinningKeys: [String]?, sslPinningKeysByHost: [String: [String]]? = nil) {
        self.mTLSIdentity = mTLSIdentity
        self.sslPinningKeys = sslPinningKeys
        self.sslPinningKeysByHost = sslPinningKeysByHost
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Handle client certificate authentication (mTLS)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            if let result = processCertificateChallenge(challenge) {
                return completionHandler(result.disposition, result.credential)
            }
            // If mTLS is not configured but client cert is requested, cancel
            return completionHandler(.cancelAuthenticationChallenge, nil)
        }

        // Handle server trust validation (SSL pinning)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            // Host-scoped pins take precedence; hosts without scoped pins use the global
            // ones. When neither applies, the host is not pinned and gets default handling.
            let pinningKeys = sslPinningKeysByHost?[Self.normalizedHost(challenge.protectionSpace.host)] ?? sslPinningKeys
            if let pinningKeys, let result = processSSLPinning(challenge, sslPinningKeys: pinningKeys) {
                return completionHandler(result.disposition, result.credential)
            }
            // If SSL pinning applies to this host but validation fails, reject
            if pinningKeys != nil {
                return completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }

        // Default handling for other authentication methods
        return completionHandler(.performDefaultHandling, nil)
    }

    /// Normalizes a host name for pin storage and lookup: DNS names are case-insensitive
    /// and may carry a trailing root-label dot, so both spellings must match the same pins.
    static func normalizedHost(_ host: String) -> String {
        var normalized = host.lowercased()
        if normalized.hasSuffix(".") {
            normalized.removeLast()
        }
        return normalized
    }

    private func processCertificateChallenge(_ challenge: URLAuthenticationChallenge) -> HChallengeResult? {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate else {
            return nil
        }

        guard let mTLSIdentity = mTLSIdentity else {
            return nil
        }

        let credential = URLCredential(identity: mTLSIdentity.identity,
                                       certificates: mTLSIdentity.certificateChain,
                                       persistence: .none)
        return HChallengeResult(disposition: .useCredential, credential: credential)
    }

    private func processSSLPinning(_ challenge: URLAuthenticationChallenge, sslPinningKeys: [String]) -> HChallengeResult? {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            return nil
        }

        return matchPins(serverTrust: serverTrust, sslPinningKeys: sslPinningKeys)
    }

    /// Evaluates the server trust and checks its certificate chain against the configured
    /// pins. Succeeds only when the trust chain is valid and any certificate in it matches
    /// one of the pins; cancels otherwise. Malformed pins are ignored so they can never
    /// produce accidental matches.
    func matchPins(serverTrust: SecTrust, sslPinningKeys: [String]) -> HChallengeResult {
        // Pins must never be matched against an untrusted chain.
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            if let error = error {
                Self.logger.log("SSL Trust Evaluation Failed", error: error, level: .error)
            }
            return (disposition: .cancelAuthenticationChallenge, credential: nil)
        }

        let validPins = Set(sslPinningKeys.filter { HSPKI.isValidPin($0) }.map { HSPKI.normalizePin($0) })
        guard !validPins.isEmpty else {
            Self.logger.log("SSL Pinning Failed: no valid pins configured", level: .error)
            return (disposition: .cancelAuthenticationChallenge, credential: nil)
        }

        // Check if any certificate in the chain matches one of the pinned keys
        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            Self.logger.log("Failed to retrieve certificate chain", level: .error)
            return (disposition: .cancelAuthenticationChallenge, credential: nil)
        }

        for certificate in certificateChain {
            guard let publicKeyHash = HSPKI.pin(for: certificate) else {
                // Unsupported key type/size (e.g. RSA-1024 or P-521 in the chain) — skip it
                Self.logger.log("Skipping certificate with unsupported key type for SSL pinning", level: .warning)
                continue
            }

            if validPins.contains(HSPKI.normalizePin(publicKeyHash)) {
                let credential = URLCredential(trust: serverTrust)
                return HChallengeResult(.useCredential, credential)
            }
        }

        // SSL pinning failed - reject connection
        Self.logger.log("SSL Pinning Failed: Public Key hash mismatch", level: .error)
        return (disposition: .cancelAuthenticationChallenge, credential: nil)
    }
}
