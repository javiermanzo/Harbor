//
//  HURLSessionDelegate.swift
//
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation
import LogBird
import Security

/// Harbor's `URLSession` delegate. It applies Harbor's transport security policy:
///
/// - **SSL pinning**: server-trust challenges from pinned hosts are evaluated against the
///   configured `base64(SHA256(SPKI))` pins.
/// - **Mutual TLS**: client-certificate challenges are answered with the configured identity,
///   only for the hosts the identity is scoped to.
/// - **Redirects**: credentials (the auth provider's header, `Authorization`, `Cookie`,
///   `Proxy-Authorization` and the other sensitive headers) are stripped when a redirect
///   leaves the original origin (scheme, host or port).
///
/// Harbor attaches it to the sessions it builds. When you provide your own session through
/// `Harbor.setCustomURLSession(_:)`, create one with `Harbor.makeURLSessionDelegate()` and
/// either install it as the session delegate or forward to it from your own delegate:
/// call ``urlSession(_:task:didReceive:completionHandler:)`` (or
/// ``handleChallenge(_:task:completionHandler:)`` from a session-level handler) and
/// ``urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)``.
///
/// The delegate captures the security configuration at creation time; create a new one
/// after changing SSL pins or mTLS.
///
/// Challenges are handled at the task level on purpose: the delegate does not implement
/// the session-level `urlSession(_:didReceive:completionHandler:)`, so `URLSession` routes
/// server-trust and client-certificate challenges to the task-level method, which knows
/// the task and can report a rejected handshake to Harbor as `HRequestError.certificate`.
public final class HURLSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {

    /// Result tuple of an authentication challenge resolution.
    typealias HChallengeResult = (disposition: URLSession.AuthChallengeDisposition, credential: URLCredential?)

    /// Logger instance for SSL/TLS related events. Toggled by `Harbor.setLoggingEnabled(_:)`.
    static let logger = LogBird(subsystem: "com.harbor", category: "ssl")

    /// Header names (lowercased) always removed from a redirect that leaves the original origin,
    /// on top of `HConfig.sensitiveHeaders` and the auth provider's header key.
    private static let crossOriginStrippedHeaders: Set<String> = ["authorization", "cookie", "proxy-authorization"]

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

    // MARK: - URLSessionTaskDelegate

    /// Handles client certificate (mTLS) and server trust (SSL pinning) challenges for a task.
    /// - Parameters:
    ///   - session: The URLSession issuing the challenge.
    ///   - task: The task the challenge belongs to.
    ///   - challenge: The authentication challenge to respond to.
    ///   - completionHandler: Completion closure called with disposition and credential.
    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handleChallenge(challenge, task: task, completionHandler: completionHandler)
    }

    /// Follows redirects, stripping credentials when the redirect leaves the original origin.
    /// `URLSession` only strips `Authorization` itself; custom auth headers and `Cookie` would
    /// otherwise be forwarded to the new host.
    /// - Parameters:
    ///   - session: The URLSession performing the redirect.
    ///   - task: The task being redirected.
    ///   - response: The redirect response.
    ///   - request: The request `URLSession` proposes for the new location.
    ///   - completionHandler: Completion closure called with the request to follow.
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let originURL = task.originalRequest?.url ?? response.url
        let authHeaderKey = (task.delegate as? HTaskContext)?.authHeaderKey
        completionHandler(Self.redirectRequest(request, originURL: originURL, authHeaderKey: authHeaderKey))
    }

    // MARK: - Challenge Handling

    /// Applies Harbor's challenge policy. Use it to forward challenges from your own delegate,
    /// including a session-level `urlSession(_:didReceive:completionHandler:)` (pass `nil` as
    /// the task there).
    ///
    /// - Client certificate: the mTLS identity is presented when one is configured and the
    ///   challenge host is in its scope; otherwise the challenge gets default handling.
    /// - Server trust: hosts with pins are evaluated against them and rejected on mismatch
    ///   or an untrusted chain; other hosts get default handling.
    /// - Anything else gets default handling.
    /// - Parameters:
    ///   - challenge: The authentication challenge to respond to.
    ///   - task: The task the challenge belongs to, when known. A rejection is reported to
    ///     the Harbor request that started it so it fails with `HRequestError.certificate`.
    ///   - completionHandler: Completion closure called with disposition and credential.
    public func handleChallenge(_ challenge: URLAuthenticationChallenge, task: URLSessionTask?, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let taskContext = task?.delegate as? HTaskContext
        let completion: @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void = { disposition, credential in
            if disposition == .cancelAuthenticationChallenge {
                taskContext?.recordTrustFailure()
            }
            completionHandler(disposition, credential)
        }

        // Handle client certificate authentication (mTLS)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            let result = processCertificateChallenge(challenge)
            return completion(result.disposition, result.credential)
        }

        // Handle server trust validation (SSL pinning)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            // Host-scoped pins take precedence; hosts without scoped pins use the global
            // ones. When neither applies, the host is not pinned and gets default handling.
            let pinningKeys = sslPinningKeysByHost?[Self.normalizedHost(challenge.protectionSpace.host)] ?? sslPinningKeys
            if let pinningKeys {
                processSSLPinning(challenge, sslPinningKeys: pinningKeys, completionHandler: completion)
                return
            }
        }

        // Default handling for other authentication methods
        return completion(.performDefaultHandling, nil)
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

    /// Answers a client certificate challenge with the configured mTLS identity. Without an
    /// identity, or when the challenge host is outside the identity's `hosts` scope, the
    /// challenge gets default handling, so no identity is offered to unexpected hosts.
    /// - Parameter challenge: The client certificate authentication challenge.
    /// - Returns: `HChallengeResult` containing disposition and credential.
    private func processCertificateChallenge(_ challenge: URLAuthenticationChallenge) -> HChallengeResult {
        guard let mTLSIdentity, mTLSIdentity.applies(toHost: challenge.protectionSpace.host) else {
            return HChallengeResult(.performDefaultHandling, nil)
        }

        let credential = URLCredential(identity: mTLSIdentity.identity,
                                       certificates: mTLSIdentity.certificateChain,
                                       persistence: .none)
        return HChallengeResult(.useCredential, credential)
    }

    // MARK: - Redirects

    /// Returns the request to follow for a redirect. When the redirect target has a different
    /// origin (scheme, host or port) than `originURL`, credentials are removed: the auth
    /// provider's header key, `Authorization`, `Cookie`, `Proxy-Authorization` and every
    /// header in `HConfig.sensitiveHeaders`. Same-origin redirects are followed unchanged.
    /// - Parameters:
    ///   - request: The request `URLSession` proposes for the new location.
    ///   - originURL: The URL the credentials were intended for.
    ///   - authHeaderKey: The header key the auth provider set on the request, if any.
    /// - Returns: The request to follow.
    static func redirectRequest(_ request: URLRequest, originURL: URL?, authHeaderKey: String?) -> URLRequest {
        guard let originURL, let targetURL = request.url, !isSameOrigin(originURL, targetURL) else {
            return request
        }

        var strippedHeaders = crossOriginStrippedHeaders.union(HConfig.sensitiveHeaders)
        if let authHeaderKey {
            strippedHeaders.insert(authHeaderKey.lowercased())
        }

        var redirected = request
        for (header, _) in request.allHTTPHeaderFields ?? [:] where strippedHeaders.contains(header.lowercased()) {
            redirected.setValue(nil, forHTTPHeaderField: header)
        }
        return redirected
    }

    /// Whether two URLs share scheme, host and port (default ports made explicit).
    private static func isSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsScheme = lhs.scheme?.lowercased()
        let rhsScheme = rhs.scheme?.lowercased()
        return lhsScheme == rhsScheme
            && lhs.host.map(normalizedHost) == rhs.host.map(normalizedHost)
            && effectivePort(of: lhs) == effectivePort(of: rhs)
    }

    /// The URL's port, or the scheme's default port when none is given.
    private static func effectivePort(of url: URL) -> Int? {
        if let port = url.port {
            return port
        }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    // MARK: - SSL Pinning

    /// Concurrent queue for server trust evaluation, keeping the potentially slow
    /// evaluation off the session's serial delegate queue.
    private static let trustEvaluationQueue = DispatchQueue(label: "harbor.ssl.trust-evaluation", qos: .userInitiated, attributes: .concurrent)

    /// Hosts already warned about for carrying certificates with unsupported key types, so
    /// the warning is logged once per host instead of on every handshake.
    private static let unsupportedKeyWarnedHosts = HLockedState<Set<String>>([])

    /// Answers a server-trust challenge against the configured pins. A challenge without
    /// a server trust is cancelled; otherwise the trust is evaluated off the session's
    /// serial delegate queue before matching the pins.
    private func processSSLPinning(_ challenge: URLAuthenticationChallenge, sslPinningKeys: [String], completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            return completionHandler(.cancelAuthenticationChallenge, nil)
        }

        evaluateAndMatchPins(serverTrust: serverTrust,
                             sslPinningKeys: sslPinningKeys,
                             host: Self.normalizedHost(challenge.protectionSpace.host),
                             completionHandler: completionHandler)
    }

    /// Evaluates the server trust asynchronously and answers with the pin-matching result:
    /// `.cancelAuthenticationChallenge` when the trust chain is invalid, otherwise the
    /// outcome of `matchPins(serverTrust:sslPinningKeys:host:)`. The synchronous evaluation
    /// inside `matchPins` reuses the cached result of the asynchronous one.
    /// - Parameters:
    ///   - serverTrust: The server trust object to evaluate.
    ///   - sslPinningKeys: The list of valid SPKI pins to match against.
    ///   - host: The host being evaluated, used to deduplicate warnings.
    ///   - completionHandler: Completion closure called with disposition and credential.
    func evaluateAndMatchPins(serverTrust: SecTrust, sslPinningKeys: [String], host: String? = nil, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
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

                let result = self.matchPins(serverTrust: serverTrust, sslPinningKeys: sslPinningKeys, host: host)
                context.completionHandler(result.disposition, result.credential)
            }
        }
    }

    /// Boxes the values handed to the trust-evaluation queue. Marked `@unchecked Sendable`:
    /// a `SecTrust` is safe to evaluate from any queue and the challenge completion
    /// handler may be invoked from any queue.
    private struct TrustEvaluationContext: @unchecked Sendable {
        /// The trust to evaluate.
        let serverTrust: SecTrust
        /// The challenge completion handler.
        let completionHandler: @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    }

    /// Evaluates the server trust and checks its certificate chain against the configured
    /// pins. Succeeds only when the trust chain is valid and any certificate in it matches
    /// one of the pins; cancels otherwise. Malformed pins are ignored so they can never
    /// produce accidental matches.
    /// - Parameters:
    ///   - serverTrust: The server trust object to evaluate.
    ///   - sslPinningKeys: The list of valid SPKI pins to match against.
    ///   - host: The host being evaluated. Certificates with unsupported key types are
    ///     reported once per host.
    /// - Returns: `HChallengeResult` containing disposition and credential.
    func matchPins(serverTrust: SecTrust, sslPinningKeys: [String], host: String? = nil) -> HChallengeResult {
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
                // Unsupported key type/size (e.g. a DSA or Ed25519 key in the chain) — skip it
                if Self.unsupportedKeyWarnedHosts.withLock({ $0.insert(host ?? "").inserted }) {
                    Self.logger.log("Skipping certificate with unsupported key type for SSL pinning (host: \(host ?? "unknown"))", level: .warning)
                }
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

// MARK: - Task Context

/// Per-task state Harbor attaches to every task it starts, as the task-specific delegate
/// (`URLSession.data(for:delegate:)` and `upload(for:fromFile:delegate:)`). It implements no delegate methods, so it never
/// changes how a session's own delegate handles the task; `HURLSessionDelegate` reads it
/// through `URLSessionTask.delegate` to learn the auth header key to strip on cross-origin
/// redirects and to report a rejected TLS handshake back to the request.
final class HTaskContext: NSObject, URLSessionTaskDelegate, Sendable {
    /// The header key the auth provider set on the request, if any.
    let authHeaderKey: String?

    /// Backing storage for `trustEvaluationFailed`; challenge answers arrive on arbitrary queues.
    private let didFailTrustEvaluation = HLockedState(false)

    /// Creates the context for one task.
    /// - Parameter authHeaderKey: The header key the auth provider set on the request, if any.
    init(authHeaderKey: String?) {
        self.authHeaderKey = authHeaderKey
    }

    /// Whether Harbor's delegate rejected a server-trust or client-certificate challenge for the task.
    var trustEvaluationFailed: Bool {
        didFailTrustEvaluation.withLock { $0 }
    }

    /// Records that a TLS challenge for the task was rejected.
    func recordTrustFailure() {
        didFailTrustEvaluation.withLock { $0 = true }
    }
}
