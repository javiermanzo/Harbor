//
//  HRequestManager+URLSessionPool.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - Session Profile

/// What a pooled session is built for. The pool knows nothing about requests: REST computes the
/// profile from the request (see `HRequestManager+RESTSession.swift`), other products pick theirs.
package enum HSessionProfile {
    /// The configuration defaults (`URLCache.shared` with `.useProtocolCachePolicy`).
    case defaults
    /// A dedicated `URLCache` and request cache policy.
    case urlCache(URLCache, URLRequest.CachePolicy)
    /// No `URLCache`: responses are never served from, nor stored into, `URLCache.shared`.
    case isolated
    /// A long-lived connection (a WebSocket): no `URLCache` and no whole-transfer resource
    /// timeout, since it may stay open longer than any transfer
    /// (`Harbor.setDefaultResourceTimeoutInterval(_:)` does not apply to it).
    case webSocket
}

// MARK: - URLSession Management
extension HRequestManager {
    /// Inputs that differentiate internally built sessions; requests with different
    /// signatures need different sessions. Timeouts are not part of it: they are set on each
    /// `URLRequest`, so requests with different timeouts share a session.
    private struct SessionSignature: Hashable {
        /// The cache configuration a session is built for.
        enum CacheSignature: Hashable {
            /// No `URLCache` (requests using `.custom` or `.disabled`).
            case isolated
            /// A `URLCache` (by identity) and the request cache policy.
            case urlCache(ObjectIdentifier, URLRequest.CachePolicy)
        }
        /// The cache configuration for the session.
        var cache: CacheSignature
        /// Whether the session handles cookies through the shared cookie storage.
        var httpShouldHandleCookies: Bool
        /// Whether the session is built for WebSocket connections (see `HSessionProfile.webSocket`).
        var isWebSocket: Bool
    }

    /// Maximum number of internally built sessions kept alive at once. Requests alternating
    /// between a few cache configurations each reuse their own session instead of rebuilding
    /// one on every switch; past this bound the least recently used session is retired.
    private static let maxCachedSessions = 4

    /// An internally built session and the last time it was handed out (a monotonic tick).
    private struct CachedSession {
        /// The session.
        let session: URLSession
        /// The tick of the last time it was handed out.
        var lastUse: UInt64
    }

    /// The internally built sessions, keyed by the configuration they were built for.
    private static var cachedSessions: [SessionSignature: CachedSession] = [:]

    /// Monotonic counter ordering session uses, for least-recently-used eviction.
    private static var sessionUseTick: UInt64 = 0

    /// Number of in-flight attempts holding each session (see `leaseURLSession(profile:)`).
    private static var sessionLeases: [ObjectIdentifier: Int] = [:]

    /// Sessions dropped from the cache while attempts still held them. They are invalidated
    /// when the last attempt releases them: creating a task on an invalidated session raises
    /// an Objective-C exception, so a session is never invalidated while it can still be used.
    private static var retiredSessions: [ObjectIdentifier: URLSession] = [:]

    /// URLSession getter that handles mTLS and SSL pinning if needed.
    ///
    /// A user-provided session (see `Harbor.setCustomURLSession`) is always used as-is and
    /// never replaced. Otherwise internally built sessions are cached per configuration and
    /// reused across requests so connections can be pooled; they are dropped when a
    /// session-affecting setting changes (see `invalidateURLSession()`).
    ///
    /// Attempts that create tasks on the session must use `leaseURLSession(profile:)` instead,
    /// so the session cannot be invalidated while they hold it.
    /// - Parameter profile: What the session is built for.
    package static func getURLSession(profile: HSessionProfile) -> URLSession {
        if let customURLSession = HConfig.shared.customURLSession {
            return customURLSession
        }

        sessionUseTick &+= 1
        let signature = sessionSignature(profile: profile)
        if let cached = cachedSessions[signature] {
            cachedSessions[signature]?.lastUse = sessionUseTick
            return cached.session
        }

        if cachedSessions.count >= maxCachedSessions,
           let leastRecentlyUsed = cachedSessions.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            cachedSessions[leastRecentlyUsed.key] = nil
            retire(leastRecentlyUsed.value.session)
        }
        let session = buildURLSession(profile: profile)
        cachedSessions[signature] = CachedSession(session: session, lastUse: sessionUseTick)
        return session
    }

    /// Returns the session for the profile and records that the caller holds it. Until the
    /// matching `releaseURLSession(_:)`, the session is never invalidated: when it is dropped
    /// from the cache meanwhile (configuration change or eviction) it is only retired. A
    /// WebSocket connection keeps its lease for as long as it is open.
    /// - Parameter profile: What the session is built for.
    /// - Returns: The session to create the tasks on.
    package static func leaseURLSession(profile: HSessionProfile) -> URLSession {
        lease(getURLSession(profile: profile))
    }

    /// Records a lease on the session.
    /// - Parameter session: The session handed out.
    /// - Returns: The same session.
    private static func lease(_ session: URLSession) -> URLSession {
        sessionLeases[ObjectIdentifier(session), default: 0] += 1
        return session
    }

    /// Releases a session obtained with `leaseURLSession(profile:)` or `leaseURLSession(for:)`.
    /// A retired session is invalidated once its last lease is released.
    /// - Parameter session: The leased session.
    package static func releaseURLSession(_ session: URLSession) {
        let id = ObjectIdentifier(session)
        guard let leases = sessionLeases[id] else { return }
        guard leases <= 1 else {
            sessionLeases[id] = leases - 1
            return
        }
        sessionLeases[id] = nil
        retiredSessions.removeValue(forKey: id)?.finishTasksAndInvalidate()
    }

    /// Number of retired sessions still held by in-flight attempts. Intended for testing.
    package static var retiredURLSessionCount: Int {
        retiredSessions.count
    }

    /// Drops the cached sessions so the next request builds one from the current configuration.
    /// Called by the `Harbor` configuration setters when session-affecting settings (timeouts,
    /// mTLS, SSL pinning, cookies, protocol classes) change. A user-provided session is never
    /// touched. Sessions still held by in-flight attempts are invalidated when those attempts
    /// release them.
    package static func invalidateURLSession() {
        let sessions = cachedSessions.values.map(\.session)
        cachedSessions.removeAll()
        sessions.forEach(retire)
    }

    /// Invalidates a session dropped from the cache once no attempt holds it: immediately when
    /// it is not leased, otherwise when its last lease is released. Running tasks finish first.
    /// - Parameter session: The session dropped from the cache.
    private static func retire(_ session: URLSession) {
        let id = ObjectIdentifier(session)
        if sessionLeases[id] != nil {
            retiredSessions[id] = session
        } else {
            session.finishTasksAndInvalidate()
        }
    }

    /// Computes the signature that uniquely identifies the required session configuration.
    /// - Parameter profile: What the session is built for.
    /// - Returns: The signature under which the session is cached.
    private static func sessionSignature(profile: HSessionProfile) -> SessionSignature {
        // The signature must mirror what buildURLSession installs so functionally identical
        // configurations share one cached session.
        let cache: SessionSignature.CacheSignature
        var isWebSocket = false
        switch profile {
        case .defaults:
            cache = .urlCache(ObjectIdentifier(URLCache.shared), .useProtocolCachePolicy)
        case .urlCache(let urlCache, let requestPolicy):
            cache = .urlCache(ObjectIdentifier(urlCache), requestPolicy)
        case .isolated:
            cache = .isolated
        case .webSocket:
            cache = .isolated
            isWebSocket = true
        }

        return SessionSignature(cache: cache, httpShouldHandleCookies: HConfig.shared.httpShouldHandleCookies, isWebSocket: isWebSocket)
    }

    /// Builds a new URLSession tailored to the configuration. The session always
    /// gets an `HURLSessionDelegate`: besides SSL pinning and mTLS it strips credentials
    /// from cross-origin redirects.
    /// - Parameter profile: What the session is built for.
    /// - Returns: A new session built from the current configuration.
    private static func buildURLSession(profile: HSessionProfile) -> URLSession {
        let configuration = URLSessionConfiguration.default
        // Each URLRequest carries its own timeout (see HURLBuilder); this is the fallback.
        configuration.timeoutIntervalForRequest = HConfig.shared.timeoutInterval
        // The whole-transfer limit is independent of the idle timeout. Leaving it unset keeps
        // the system default (7 days) so long transfers are not cut off. It never applies to
        // WebSocket connections, which may legitimately stay open longer than any transfer.
        if case .webSocket = profile {} else if let resourceTimeoutInterval = HConfig.shared.resourceTimeoutInterval {
            configuration.timeoutIntervalForResource = resourceTimeoutInterval
        }
        // Cookie handling is governed at the session-configuration level on Darwin; the
        // request-level flag set by HURLBuilder alone is not enough.
        configuration.httpShouldSetCookies = HConfig.shared.httpShouldHandleCookies

        if let protocolClasses = HConfig.shared.protocolClasses {
            configuration.protocolClasses = protocolClasses
        }

        switch profile {
        case .defaults:
            break
        case .urlCache(let cache, let requestPolicy):
            configuration.urlCache = cache
            configuration.requestCachePolicy = requestPolicy
        case .isolated, .webSocket:
            // An isolated zero-capacity URLCache, so responses are never served from — nor
            // stored into — URLCache.shared.
            configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        }

        let sessionDelegate = HURLSessionDelegate(mTLSIdentity: HConfig.shared.mTLSIdentity,
                                                  sslPinningKeys: HConfig.shared.sslPinningKeys,
                                                  sslPinningKeysByHost: HConfig.shared.sslPinningKeysByHost)
        return URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
    }
}
