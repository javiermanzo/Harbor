//
//  Harbor.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import Security

/// Harbor - Protocol-oriented networking framework for Swift.
///
/// Features: Caching, Authentication, SSL/TLS Security, Mocking, Async/Await, Retry Logic
@HRequestManagerActor
public enum Harbor {}

// MARK: - Configuration

public extension Harbor {

    /// Configures authentication provider for requests requiring auth.
    ///
    /// Cached responses of requests that need auth are namespaced by a SHA-256 digest of the
    /// authorization header they were fetched with, so a new provider (or a new credential)
    /// never reads entries stored for another one. Replacing the provider does not delete
    /// those entries: call `Harbor.clearAllCache()` on logout to remove a previous user's
    /// data from memory and disk. It does forget the credentials remembered for offline cache
    /// lookups, so the new provider is consulted again.
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    /// - Parameter authProvider: The provider supplying authorization headers, or `nil` to remove it.
    static func setAuthProvider(_ authProvider: HAuthProviderProtocol?) {
        HConfig.shared.authProvider = authProvider
        HRequestManager.forgetRememberedAuthHeaders()
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
    /// - Parameter mTLS: The mTLS configuration.
    /// - Throws: `HMTLSError` when the identity could not be extracted from the P12
    ///   (file missing, wrong password, malformed, no identity). mTLS stays disabled in that case.
    static func setMTLS(_ mTLS: HMTLS) async throws {

        do {
            let identity = try await Task.detached {
                try await mTLS.extractIdentity()
            }.value
            HConfig.shared.mTLSIdentity = identity
            HRequestManager.invalidateURLSession()
            warnIfCustomURLSessionBypassesSecurity(afterSecurityChange: true)
        } catch {
            HConfig.shared.mTLSIdentity = nil
            HRequestManager.invalidateURLSession()
            HLogger.log("mTLS identity could not be configured", error: error, level: .error)
            throw error
        }
    }

    /// Disables mutual TLS by clearing any configured client identity.
    static func clearMTLS() {
        HConfig.shared.mTLSIdentity = nil
        HRequestManager.invalidateURLSession()
    }

    /// Enables SSL pinning with SHA256 hashes of the certificate's SubjectPublicKeyInfo (SPKI),
    /// base64 encoded. Provide multiple keys to support key rotation (backup pins).
    /// The pins apply to every host that has no host-scoped pins (see
    /// `setSSLPinningKeys(_:forHosts:)`). Use `Harbor.computePin(for:)` to generate pins from a certificate.
    /// - Parameter sslPinningKeys: The `base64(SHA256(SPKI))` pins to accept, or `nil` to disable global pinning.
    static func setSSLPinningKeys(_ sslPinningKeys: [String]?) {
        HConfig.shared.sslPinningKeys = sslPinningKeys
        HRequestManager.invalidateURLSession()
        warnIfCustomURLSessionBypassesSecurity(afterSecurityChange: true)
    }

    /// Enables SSL pinning scoped to specific hosts. Challenges from these hosts are
    /// validated against the given pins; hosts not configured here fall back to the
    /// global pins set with `setSSLPinningKeys(_:)` or, when none are set, to default handling.
    /// Passing `nil` removes the pins for the given hosts.
    /// Host names are normalized (lowercased, without a trailing root-label dot) before
    /// being stored and matched against `URLProtectionSpace.host`.
    /// - Parameters:
    ///   - sslPinningKeys: The pins for the hosts, or `nil` to stop pinning them.
    ///   - hosts: The hosts the pins apply to (matched against `URLProtectionSpace.host`).
    static func setSSLPinningKeys(_ sslPinningKeys: [String]?, forHosts hosts: [String]) {
        if let sslPinningKeys {
            var keysByHost = HConfig.shared.sslPinningKeysByHost ?? [:]
            for host in hosts {
                let normalizedHost = HURLSessionDelegate.normalizedHost(host)
                guard !normalizedHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    HLogger.log("SSL pinning host keys must not be empty", level: .warning)
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
        warnIfCustomURLSessionBypassesSecurity(afterSecurityChange: true)
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
    ///   configured and the custom session does not use Harbor's delegate.
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
        warnIfCustomURLSessionBypassesSecurity(afterSecurityChange: false)
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
                            sslPinningKeysByHost: HConfig.shared.sslPinningKeysByHost)
    }

    /// Sets default cache type for requests without explicit cache settings.
    /// Default is .urlCache.
    ///
    /// The memory limit of the custom cache follows the default configuration when it is
    /// `.custom`; per-request configurations can only raise it, never lower it.
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    /// - Parameter cacheType: The cache type applied to GET requests whose `cacheType` is `nil`.
    static func setDefaultCacheType(_ cacheType: HCache.CacheType) {
        HConfig.shared.cacheType = cacheType
        HCache.Manager.shared.applyDefaultCacheType(cacheType)
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

    /// Whether registered mocks currently answer requests.
    ///
    /// Default: `true` in DEBUG builds and `false` otherwise. Change it with `setMocksEnabled(_:)`.
    static var mocksEnabled: Bool {
        HConfig.shared.mocksEnabled
    }

    /// Turns mocks on or off. While mocks are off, registered mocks are kept but ignored and
    /// every request reaches the network.
    ///
    /// By default mocks are on in DEBUG builds and off in release builds, so a mock left
    /// registered by mistake never answers in production. Call `setMocksEnabled(true)` to use
    /// them in a release build (e.g. a UI-test or demo configuration).
    /// - Note: This is a method rather than a `get set` property to allow cross-actor mutation, as Swift forbids mutating actor-isolated static properties from outside the actor's context.
    /// - Parameter enabled: Whether registered mocks answer requests.
    static func setMocksEnabled(_ enabled: Bool) {
        HConfig.shared.mocksEnabled = enabled
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
    /// `token`, `secret`, `session_id`, …) and the header key the auth provider's credential
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
    /// Logs a warning when a custom session is configured together with SSL pinning or mTLS,
    /// since those are enforced by Harbor's session delegate. Logged regardless of debug
    /// logging, as the misconfiguration silently disables security checks.
    /// - Parameter afterSecurityChange: Whether pins or mTLS just changed. A custom session
    ///   using Harbor's delegate then holds a stale snapshot and must be rebuilt.
    static func warnIfCustomURLSessionBypassesSecurity(afterSecurityChange: Bool) {
        guard let warning = customURLSessionSecurityWarning(afterSecurityChange: afterSecurityChange) else { return }
        HLogger.securityWarning(warning)
    }

    /// The warning that applies to the current custom session and security configuration.
    /// - Parameter afterSecurityChange: Whether pins or mTLS just changed (see
    ///   `warnIfCustomURLSessionBypassesSecurity(afterSecurityChange:)`).
    /// - Returns: The warning text, or `nil` when none is needed.
    static func customURLSessionSecurityWarning(afterSecurityChange: Bool) -> String? {
        guard let customURLSession = HConfig.shared.customURLSession else { return nil }
        let hasTransportSecurity = HConfig.shared.mTLSIdentity != nil
            || HConfig.shared.sslPinningKeys != nil
            || HConfig.shared.sslPinningKeysByHost != nil

        if customURLSession.delegate is HURLSessionDelegate {
            guard afterSecurityChange else { return nil }
            return "SSL pinning / mTLS configuration changed while a custom URLSession is set. Its HURLSessionDelegate keeps the previous configuration; create a new one with Harbor.makeURLSessionDelegate() and set a new session."
        } else if hasTransportSecurity {
            return "SSL pinning / mTLS are configured but the custom URLSession does not use Harbor's delegate, so they are NOT enforced for its requests. Create the session with Harbor.makeURLSessionDelegate() or forward its delegate callbacks to one."
        }
        return nil
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

// MARK: - Mocking

public extension Harbor {

    /// Registers a mock that answers every request of `mock.request` while mocks are enabled
    /// (see `setMocksEnabled(_:)`). Any mock or mock sequence already registered for that
    /// request type is replaced.
    /// - Parameter mock: The response to answer requests of `mock.request` with.
    static func register(mock: HMock) {
        HMocker.register(mock: mock)
    }

    /// Registers a scripted sequence of mock responses for a request type. Each attempt of a
    /// request of that type (retries included) resolves to the next response in order; the last
    /// one repeats thereafter. Any mock or mock sequence already registered for that request
    /// type is replaced. A sequence with no responses is ignored.
    /// - Parameter mockSequence: The responses to play back for requests of `mockSequence.request`.
    static func register(mockSequence: HMockSequence) {
        HMocker.register(mockSequence: mockSequence)
    }

    /// Removes the mock or mock sequence registered for a request type, so its requests reach
    /// the network again.
    /// - Parameter requestType: The request type that stops being mocked.
    static func removeMock(for requestType: HRequestBaseRequestProtocol.Type) {
        HMocker.removeMock(for: requestType)
    }

    /// Removes every registered mock and mock sequence, and resets the mock call counts.
    static func removeAllMocks() {
        HMocker.removeAll()
    }

    /// The number of times requests of the given type have been answered by a mock. Every
    /// attempt counts, so a request retried twice adds 3.
    /// - Parameter requestType: The request type whose mock resolutions are counted.
    /// - Returns: The number of mocked attempts since launch or the last `removeAllMocks()`.
    static func mockCallCount(for requestType: HRequestBaseRequestProtocol.Type) -> Int {
        HMocker.callCount(for: requestType)
    }

    /// Whether a mock or mock sequence is currently registered for the request type.
    /// - Parameter requestType: The request type to look up.
    /// - Returns: `true` when requests of that type are answered by a mock while mocks are enabled.
    static func isMockRegistered(for requestType: HRequestBaseRequestProtocol.Type) -> Bool {
        HMocker.isRegistered(requestType)
    }
}

// MARK: - Cache Management

public extension Harbor {

    /// Clears all cached data: the custom cache (memory and disk), `URLCache.shared`, and the
    /// URLCache of the configured default cache type and custom session when they differ.
    /// The credentials remembered for offline cache lookups are forgotten as well.
    static func clearAllCache() async {
        HRequestManager.forgetRememberedAuthHeaders()
        await HCache.Manager.shared.clearAllCache()
        URLCache.shared.removeAllCachedResponses()

        if case .urlCache(let cache, _) = HConfig.shared.cacheType, cache !== URLCache.shared {
            cache.removeAllCachedResponses()
        }

        if let sessionCache = HConfig.shared.customURLSession?.configuration.urlCache, sessionCache !== URLCache.shared {
            sessionCache.removeAllCachedResponses()
        }
    }
}
