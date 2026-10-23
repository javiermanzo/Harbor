//
//  Harbor.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import Security

/// Harbor's global configuration, shared by every product (REST, JSON-RPC, WebSocket):
/// authentication, SSL pinning, mTLS, the custom session, timeouts, cookies and logging.
/// Product-specific settings are added by `Harbor` (cache, mocks) and live on `HarborJRPC`
/// and `HarborWebSocket`.
@HRequestManagerActor
public enum Harbor {}

// MARK: - Configuration

public extension Harbor {

    /// Configures authentication provider for requests requiring auth.
    ///
    /// Cached responses of requests that need auth are namespaced by a SHA-256 digest of the
    /// authorization header they were fetched with, so a new provider (or a new credential)
    /// never reads entries stored for another one. Replacing the provider does not delete
    /// those entries: with the REST product, call `Harbor.clearAllCache()` on logout to remove
    /// a previous user's data from memory and disk. It does forget the credentials remembered
    /// for offline cache lookups, so the new provider is consulted again, and a `401` refresh
    /// in flight stops using the old provider. Already open `HWebSocket` connections are not
    /// affected: close them on logout.
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    /// - Parameter authProvider: The provider supplying authorization headers, or `nil` to remove it.
    static func setAuthProvider(_ authProvider: HAuthProviderProtocol?) {
        HConfig.shared.authProvider = authProvider
        HRequestManager.authGeneration &+= 1
        HRequestManager.completedAuthFailures.removeAll()
        HRequestManager.authProviderDidChange?()
    }

    /// Sets default headers applied to all requests.
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    /// - Parameter defaultHeaderParameters: Headers merged into every request (request-specific headers take precedence), or `nil` for none.
    static func setDefaultHeaderParameters(_ defaultHeaderParameters: [String: String]?) {
        HConfig.shared.defaultHeaderParameters = defaultHeaderParameters
    }

    /// Configures mutual TLS for client certificate authentication.
    /// The P12 file is read and imported off the actor so in-flight requests are not blocked.
    /// The identity is only presented to the hosts given in `HMTLS(p12FileUrl:hosts:passwordProvider:)`
    /// (every host when `hosts` is `nil`).
    ///
    /// On iOS-family platforms the identity is always imported into process memory only. On
    /// macOS it is memory-only from macOS 15; on macOS 14 and earlier `SecPKCS12Import` has
    /// no in-memory option and persists the imported private key and certificates to the
    /// default (login) keychain.
    /// The latest call wins: when `setMTLS(_:)` or `clearMTLS()` is called again while the
    /// import is running (e.g. waiting for a biometric prompt), this call changes nothing
    /// when it finishes and throws `CancellationError`.
    /// - Parameter mTLS: The mTLS configuration.
    /// - Throws: `HMTLSError` when the identity could not be extracted from the P12
    ///   (file missing, wrong password, malformed, no identity); mTLS is disabled in that case.
    ///   `CancellationError` when a later call superseded this one.
    static func setMTLS(_ mTLS: HMTLS) async throws {
        HConfig.shared.mTLSGeneration &+= 1
        let generation = HConfig.shared.mTLSGeneration

        let result: Result<HMTLSIdentity, Error>
        do {
            result = .success(try await Task.detached {
                try await mTLS.extractIdentity()
            }.value)
        } catch {
            result = .failure(error)
        }

        guard generation == HConfig.shared.mTLSGeneration else {
            throw CancellationError()
        }

        switch result {
        case .success(let identity):
            HConfig.shared.mTLSIdentity = identity
            HRequestManager.invalidateURLSession()
            warnIfCustomURLSessionBypassesSecurity()
        case .failure(let error):
            HConfig.shared.mTLSIdentity = nil
            HRequestManager.invalidateURLSession()
            warnIfCustomURLSessionBypassesSecurity()
            HLogger.log("mTLS identity could not be configured", error: error, level: .error)
            throw error
        }
    }

    /// Disables mutual TLS by clearing any configured client identity. A `setMTLS(_:)` call
    /// still importing its identity is superseded and changes nothing.
    static func clearMTLS() {
        HConfig.shared.mTLSGeneration &+= 1
        HConfig.shared.mTLSIdentity = nil
        HRequestManager.invalidateURLSession()
        warnIfCustomURLSessionBypassesSecurity()
    }

    /// Enables SSL pinning with SHA256 hashes of the certificate's SubjectPublicKeyInfo (SPKI),
    /// base64 encoded. Provide multiple keys to support key rotation (backup pins).
    /// The pins apply to every host that has no host-scoped pins (see
    /// `setSSLPinningKeys(_:forHosts:)`). Use `Harbor.computePin(for:)` to generate pins from a certificate.
    /// - Parameter sslPinningKeys: The `base64(SHA256(SPKI))` pins to accept, or `nil` to disable global pinning.
    static func setSSLPinningKeys(_ sslPinningKeys: [String]?) {
        HConfig.shared.sslPinningKeys = sslPinningKeys
        HRequestManager.invalidateURLSession()
        warnIfCustomURLSessionBypassesSecurity()
    }

    /// Enables SSL pinning scoped to specific hosts. Challenges from these hosts are
    /// validated against the given pins; hosts not configured here fall back to the
    /// global pins set with `setSSLPinningKeys(_:)` or, when none are set, to default handling.
    /// Passing `nil` removes the pins for the given hosts.
    /// Host names are normalized (surrounding whitespace removed, lowercased, without a
    /// trailing root-label dot) before being stored and matched against
    /// `URLProtectionSpace.host`. They must be bare host names (`api.example.com`, punycode
    /// for internationalized names), matched exactly (subdomains are not included): a value
    /// with a scheme, a port, a path or non-ASCII characters can never match, so it logs a
    /// security warning and is skipped.
    /// - Parameters:
    ///   - sslPinningKeys: The pins for the hosts, or `nil` to stop pinning them.
    ///   - hosts: The hosts the pins apply to (matched against `URLProtectionSpace.host`).
    static func setSSLPinningKeys(_ sslPinningKeys: [String]?, forHosts hosts: [String]) {
        if let sslPinningKeys {
            var keysByHost = HConfig.shared.sslPinningKeysByHost ?? [:]
            for host in hosts {
                let normalizedHost = HURLSessionDelegate.normalizedHost(host)
                guard !normalizedHost.isEmpty else {
                    HLogger.securityWarning("SSL pinning host names must not be empty.")
                    continue
                }
                guard isPinnableHost(normalizedHost) else {
                    HLogger.securityWarning("SSL pinning host \"\(host)\" is not a bare host name (no scheme, port, path, spaces or non-ASCII characters; use punycode) and can never match: it is ignored.")
                    continue
                }
                keysByHost[normalizedHost] = sslPinningKeys
            }
            HConfig.shared.sslPinningKeysByHost = keysByHost
        } else {
            guard var keysByHost = HConfig.shared.sslPinningKeysByHost else { return }
            for host in hosts {
                keysByHost.removeValue(forKey: HURLSessionDelegate.normalizedHost(host))
            }
            HConfig.shared.sslPinningKeysByHost = keysByHost.isEmpty ? nil : keysByHost
        }
        HRequestManager.invalidateURLSession()
        warnIfCustomURLSessionBypassesSecurity()
    }

    /// Computes the SSL pin for a certificate: `base64(SHA256(SPKI))`.
    /// This matches the output of:
    /// `openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64`
    /// - Parameter certificate: The certificate to pin.
    /// - Returns: The pin string, or `nil` if the certificate's key type is unsupported.
    static func computePin(for certificate: SecCertificate) -> String? {
        HSPKI.pin(for: certificate)
    }

    /// Sets custom URLSession for all Harbor requests.
    /// Pass `nil` to restore the default Harbor URLSession.
    ///
    /// - Important: The session is used as-is. Harbor's SSL pinning, mTLS and credential
    ///   stripping on cross-origin redirects are implemented by its session delegate, so they
    ///   are **not applied** to a custom session unless its delegate is the one returned by
    ///   `Harbor.makeURLSessionDelegate()`, or your own delegate forwards to it. Create that
    ///   delegate after configuring pins and mTLS: it captures the configuration at creation.
    ///   A warning is logged (even with debug logging disabled) when pins or mTLS are
    ///   configured and the custom session's delegate is not an `HURLSessionDelegate`, and
    ///   when its `HURLSessionDelegate` was created before the last pin or mTLS change.
    ///
    /// ```swift
    /// let delegate = await Harbor.makeURLSessionDelegate()
    /// let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    /// await Harbor.setCustomURLSession(session)
    /// ```
    ///
    /// Per-request and default timeouts still apply (they are set on each `URLRequest`);
    /// the session's cache, cookie and resource-timeout settings are the session's own.
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    /// - Parameter customURLSession: The session to send every request through, or `nil` to go back to Harbor's own sessions.
    static func setCustomURLSession(_ customURLSession: URLSession?) {
        HConfig.shared.customURLSession = customURLSession
        warnIfCustomURLSessionBypassesSecurity()
    }

    /// Returns a `URLSession` delegate applying Harbor's current SSL pinning and mTLS
    /// configuration and its redirect policy (credentials are stripped when a redirect leaves
    /// the original origin). Use it for a session passed to `setCustomURLSession(_:)`, either
    /// as the session delegate or by forwarding your delegate's challenge and redirect
    /// callbacks to it.
    ///
    /// The delegate captures the configuration at the time of the call; create a new one
    /// (and a new session) after changing pins or mTLS.
    /// - Returns: A delegate configured with the current security settings.
    static func makeURLSessionDelegate() -> HURLSessionDelegate {
        HURLSessionDelegate(mTLSIdentity: HConfig.shared.mTLSIdentity,
                            sslPinningKeys: HConfig.shared.sslPinningKeys,
                            sslPinningKeysByHost: HConfig.shared.sslPinningKeysByHost,
                            securityGeneration: HConfig.shared.securityGeneration)
    }

    /// Sets default timeout interval for requests.
    /// Default is 15 seconds. It is set on every `URLRequest` (unless the request overrides
    /// `timeoutInterval`), so it also applies to custom sessions, and bounds the idle time
    /// between packets rather than the whole transfer (see `setDefaultResourceTimeoutInterval(_:)`).
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    /// - Parameter timeout: The idle timeout applied to every request, in seconds.
    static func setDefaultTimeoutInterval(_ timeout: TimeInterval) {
        HConfig.shared.timeoutInterval = timeout
        HRequestManager.invalidateURLSession()
    }

    /// Sets the maximum time a whole transfer may take (including retries of the
    /// underlying connection) in the sessions Harbor builds, independently of the per-request
    /// idle timeout set with `setDefaultTimeoutInterval(_:)`.
    /// Default is `nil`, which keeps the system default of 7 days so long downloads and
    /// uploads are not cut off. Not applied to a session set with `setCustomURLSession(_:)`.
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    /// - Parameter timeout: The resource timeout, or `nil` for the system default.
    static func setDefaultResourceTimeoutInterval(_ timeout: TimeInterval?) {
        HConfig.shared.resourceTimeoutInterval = timeout
        HRequestManager.invalidateURLSession()
    }

    /// Configures whether debug logs are enabled.
    ///
    /// Default is `true` in DEBUG builds and `false` otherwise. Enabling it also turns on the
    /// underlying LogBird loggers, so logs are recorded in release builds too. Security
    /// warnings (e.g. SSL pinning not enforced by a custom session) are recorded regardless.
    /// - Parameter enabled: If true, logs are recorded. If false, no debug logs are recorded.
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    static func setLoggingEnabled(_ enabled: Bool) {
        HLogger.setLoggingEnabled(enabled)
    }

    /// Configures sensitive-key redaction for debug logs.
    ///
    /// A key is sensitive when it contains any of the configured values;
    /// matching is case-insensitive and ignores separators, so `accessToken`,
    /// `access-token` and `ACCESS_TOKEN` all match `token`.
    ///
    /// Harbor starts from LogBird's global defaults, which already cover
    /// common HTTP auth fields (`authorization`, `auth`, `cookie`, `apikey`,
    /// `bearer`, `credentials`, `token`, `password`, `secret`, `privatekey`).
    ///
    /// These keys apply to every value Harbor prints: request and response headers, query
    /// values, path/query/body parameters, cURL commands, response bodies and
    /// `HRequestError.api` descriptions. On top of them Harbor always redacts its built-in
    /// HTTP credential keys (`authorization`, `cookie`, `set-cookie`, `x-api-key`, `password`,
    /// `token`, `secret`, `session_id`, `sec-websocket-protocol`, …) and the header key the auth provider's credential
    /// is sent under, even after `.set` or `.clear`; use `setLogSensitiveValues(true)` to
    /// print every value.
    ///
    /// Examples:
    /// ```swift
    /// await Harbor.updateLogSensitiveKeys(.set(["signature", "otp"])) // replace the full set
    /// await Harbor.updateLogSensitiveKeys(.add(["signature"]))          // extend the current set
    /// await Harbor.updateLogSensitiveKeys(.reset)                       // restore the defaults
    /// await Harbor.updateLogSensitiveKeys(.clear)                       // drop the configurable keys
    /// ```
    ///
    /// - Parameter action: The update to apply to the sensitive-key set.
    static func updateLogSensitiveKeys(_ action: HLoggingSensitiveKeyAction) {
        HLogger.sensitiveKeys(action)
    }

    /// Configures whether sensitive values are printed unredacted: request and response
    /// headers (Authorization, Cookie, Set-Cookie, X-API-Key, the auth provider's header, …),
    /// query values, body fields (e.g. `password`, `access_token`) in logged parameters, cURL
    /// commands and response bodies, and `HRequestError.api` body previews.
    /// See `updateLogSensitiveKeys(_:)` for which keys are sensitive.
    /// - Parameter enabled: If true, real values are printed. If false (default), values are redacted as `<redacted>`.
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    static func setLogSensitiveValues(_ enabled: Bool) {
        HConfig.shared.logSensitiveValues = enabled
    }

    /// Configures whether requests handle cookies through the shared cookie storage.
    /// Default is false.
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    /// - Parameter enabled: Whether Harbor's sessions send and store cookies from `HTTPCookieStorage.shared`.
    static func setHTTPShouldHandleCookies(_ enabled: Bool) {
        HConfig.shared.httpShouldHandleCookies = enabled
        HRequestManager.invalidateURLSession()
    }

    /// Configures whether DEBUG/simulator builds assume network availability instead of
    /// trusting the connectivity monitor. Default is true; set to false to exercise
    /// `.noConnection` flows in debug builds.
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    /// - Parameter value: Whether DEBUG/simulator builds skip the connectivity pre-check.
    static func setAssumeNetworkAvailableInDebug(_ value: Bool) {
        HConfig.shared.assumeNetworkAvailableInDebug = value
    }
}

// MARK: - Custom Session Security Warnings

extension Harbor {
    /// Logs a warning when a custom session does not enforce the current SSL pinning and mTLS
    /// configuration, which Harbor's session delegate implements. Logged regardless of debug
    /// logging, as the misconfiguration silently disables security checks.
    static func warnIfCustomURLSessionBypassesSecurity() {
        guard let warning = customURLSessionSecurityWarning() else { return }
        HLogger.securityWarning(warning)
    }

    /// The warning that applies to the current custom session and security configuration.
    /// - Returns: The warning text, or `nil` when none is needed.
    static func customURLSessionSecurityWarning() -> String? {
        guard let customURLSession = HConfig.shared.customURLSession else { return nil }
        let hasTransportSecurity = HConfig.shared.mTLSIdentity != nil
            || HConfig.shared.sslPinningKeys != nil
            || HConfig.shared.sslPinningKeysByHost != nil

        if let delegate = customURLSession.delegate as? HURLSessionDelegate {
            guard delegate.securityGeneration != HConfig.shared.securityGeneration else { return nil }
            return "The custom URLSession's HURLSessionDelegate was created before the last SSL pinning / mTLS change and keeps the previous configuration; create a new one with Harbor.makeURLSessionDelegate() and set a new session."
        } else if hasTransportSecurity {
            return "SSL pinning / mTLS are configured but the custom URLSession's delegate is not an HURLSessionDelegate, so they are NOT enforced for its requests unless that delegate forwards its challenge and redirect callbacks to one (then ignore this warning). Create the session with Harbor.makeURLSessionDelegate()."
        }
        return nil
    }

    /// Whether `host` can match a `URLProtectionSpace.host`: an ASCII host name or IP
    /// address without a scheme, port, path or whitespace. (An IPv6 address has several colons;
    /// a single one is a `host:port`.)
    /// - Parameter host: The normalized host.
    static func isPinnableHost(_ host: String) -> Bool {
        !host.contains("/") && !host.contains(where: \.isWhitespace) && host.allSatisfy(\.isASCII)
            && host.filter { $0 == ":" }.count != 1
    }
}

// MARK: - Network Monitoring

extension Harbor {

    /// Stops the internal network connectivity monitor and resets its state.
    /// The monitor restarts lazily on the next connectivity check. Used by tests.
    static func stopNetworkMonitor() {
        HRequestManager.connectivityMonitor.stop()
    }
}
