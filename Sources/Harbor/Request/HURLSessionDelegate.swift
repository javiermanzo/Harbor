//
//  HURLSessionDelegate.swift
//
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation
import LogBird
import Security

/// Custom `URLSessionDelegate` handling client certificate (mTLS) authentication and SSL pinning challenges.
final class HURLSessionDelegate: NSObject, URLSessionDelegate, Sendable {

    /// Result tuple of an authentication challenge resolution.
    typealias HChallengeResult = (disposition: URLSession.AuthChallengeDisposition, credential: URLCredential?)

    /// Logger instance for SSL/TLS related events.
    private static let logger = LogBird(subsystem: "com.harbor", category: "ssl")

    /// Client identity configuration for mutual TLS.
    private let mTLSIdentity: HMTLSIdentity?
    /// Global SSL pinning keys.
    private let sslPinningKeys: [String]?
    /// Host-scoped SSL pinning keys.
    private let sslPinningKeysByHost: [String: [String]]?

    /// Creates a session delegate with optional mTLS identity and SSL pinning keys.
    /// - Parameters:
    ///   - mTLSIdentity: Client identity for mTLS.
    ///   - sslPinningKeys: Global SSL pinning keys.
    ///   - sslPinningKeysByHost: Scoped SSL pinning keys mapped by host name.
    init(mTLSIdentity: HMTLSIdentity?, sslPinningKeys: [String]?, sslPinningKeysByHost: [String: [String]]? = nil) {
        self.mTLSIdentity = mTLSIdentity
        self.sslPinningKeys = sslPinningKeys
        self.sslPinningKeysByHost = sslPinningKeysByHost
    }

    /// Handles URLSession authentication challenges for client certificates (mTLS) and server trust (SSL pinning).
    /// - Parameters:
    ///   - session: The URLSession issuing the challenge.
    ///   - challenge: The authentication challenge to respond to.
    ///   - completionHandler: Completion closure called with disposition and credential.
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
            if let pinningKeys {
                processSSLPinning(challenge, sslPinningKeys: pinningKeys, completionHandler: completionHandler)
                return
            }
        }

        // Default handling for other authentication methods
        return completionHandler(.performDefaultHandling, nil)
    }

    /// Normalizes a host name for pin storage and lookup: DNS names are case-insensitive
    /// and may carry a trailing root-label dot, so both spellings must match the same pins.
    /// - Parameter host: The raw host name string.
    /// - Returns: Normalized lowercase host name without trailing dot.
    static func normalizedHost(_ host: String) -> String {
        var normalized = host.lowercased()
        if normalized.hasSuffix(".") {
            normalized.removeLast()
        }
        return normalized
    }

    /// Processes a client certificate challenge using the configured mTLS identity.
    /// - Parameter challenge: The client certificate authentication challenge.
    /// - Returns: `HChallengeResult` containing disposition and credential, or `nil` if mTLS is not configured.
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

    /// Concurrent queue for server trust evaluation, keeping the potentially slow
    /// evaluation off the session's serial delegate queue.
    private static let trustEvaluationQueue = DispatchQueue(label: "harbor.ssl.trust-evaluation", qos: .userInitiated, attributes: .concurrent)

    /// Answers a server-trust challenge against the configured pins. A challenge without
    /// a server trust is cancelled; otherwise the trust is evaluated off the session's
    /// serial delegate queue before matching the pins.
    private func processSSLPinning(_ challenge: URLAuthenticationChallenge, sslPinningKeys: [String], completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            return completionHandler(.cancelAuthenticationChallenge, nil)
        }

        evaluateAndMatchPins(serverTrust: serverTrust, sslPinningKeys: sslPinningKeys, completionHandler: completionHandler)
    }

    /// Evaluates the server trust asynchronously and answers with the pin-matching result:
    /// `.cancelAuthenticationChallenge` when the trust chain is invalid, otherwise the
    /// outcome of `matchPins(serverTrust:sslPinningKeys:)`. The synchronous evaluation
    /// inside `matchPins` reuses the cached result of the asynchronous one.
    /// - Parameters:
    ///   - serverTrust: The server trust object to evaluate.
    ///   - sslPinningKeys: The list of valid SPKI pins to match against.
    ///   - completionHandler: Completion closure called with disposition and credential.
    func evaluateAndMatchPins(serverTrust: SecTrust, sslPinningKeys: [String], completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let context = TrustEvaluationContext(serverTrust: serverTrust, completionHandler: completionHandler)

        // SecTrustEvaluateAsyncWithError requires being invoked on the queue it is given.
        Self.trustEvaluationQueue.async {
            SecTrustEvaluateAsyncWithError(context.serverTrust, Self.trustEvaluationQueue) { serverTrust, success, error in
                guard success else {
                    if let error {
                        Self.logger.log("SSL Trust Evaluation Failed", error: error, level: .error)
                    }
                    return context.completionHandler(.cancelAuthenticationChallenge, nil)
                }

                let result = self.matchPins(serverTrust: serverTrust, sslPinningKeys: sslPinningKeys)
                context.completionHandler(result.disposition, result.credential)
            }
        }
    }

    /// Boxes the values handed to the trust-evaluation queue. Marked `@unchecked Sendable`:
    /// a `SecTrust` is safe to evaluate from any queue and the challenge completion
    /// handler may be invoked from any queue.
    private struct TrustEvaluationContext: @unchecked Sendable {
        let serverTrust: SecTrust
        let completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    }

    /// Evaluates the server trust and checks its certificate chain against the configured
    /// pins. Succeeds only when the trust chain is valid and any certificate in it matches
    /// one of the pins; cancels otherwise. Malformed pins are ignored so they can never
    /// produce accidental matches.
    /// - Parameters:
    ///   - serverTrust: The server trust object to evaluate.
    ///   - sslPinningKeys: The list of valid SPKI pins to match against.
    /// - Returns: `HChallengeResult` containing disposition and credential.
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
