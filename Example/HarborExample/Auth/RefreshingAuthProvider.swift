//
//  RefreshingAuthProvider.swift
//  HarborExample
//
//  Authentication provider for the token-refresh demo
//

import Foundation
import Harbor
import LogBird

/// Auth provider for the token-refresh demo.
///
/// It starts holding an expired access token. The demo stub server rejects that token with
/// a 401. Harbor then asks for the current header: if it already differs from the rejected
/// one (another request refreshed it meanwhile) the request is re-sent with it without
/// calling `authFailed()`. Otherwise Harbor calls `authFailed()` exactly once (concurrent
/// requests rejected with the same header share that call), where this provider refreshes
/// the token, and re-sends the request once with the new header. A request that still
/// fails after that ends with `.authNeeded`.
///
/// `getAuthorizationHeader()` only returns the current token: the refresh lives in
/// `authFailed()`. It is an `actor`, so the UI can read `refreshCount` and call `reset()`
/// while Harbor uses it, without a data race.
actor RefreshingAuthProvider {
    private var accessToken = AuthDemoStubProtocol.expiredToken
    private(set) var refreshCount = 0

    private static let logger = LogBird(subsystem: "com.harbor.example", category: "Auth")
}

// MARK: - Demo State

extension RefreshingAuthProvider {
    /// Restores the initial state so the demo can run again with an expired token.
    func reset() {
        accessToken = AuthDemoStubProtocol.expiredToken
        refreshCount = 0
    }
}

// MARK: - HAuthProviderProtocol

extension RefreshingAuthProvider: HAuthProviderProtocol {
    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        HAuthorizationHeader(key: "Authorization", value: "Bearer \(accessToken)")
    }

    func authFailed() async {
        // Called once per request after a 401 that the current header cannot recover from.
        // A real provider would call its token endpoint here (or log the user out).
        Self.logger.log("Server rejected the access token; refreshing it", level: .info)
        accessToken = AuthDemoStubProtocol.validToken
        refreshCount += 1
    }
}
