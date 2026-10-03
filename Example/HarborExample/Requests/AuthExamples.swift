//
//  AuthExamples.swift
//  HarborExample
//
//  Authentication provider examples for Harbor
//

import Foundation
import Harbor
import LogBird

enum AuthError: Error {
    case noRefreshToken
}

// MARK: - Token Auth Provider

/// Token-based authentication provider
final class TokenAuthProvider: HAuthProviderProtocol, @unchecked Sendable {
    private var accessToken: String?
    private var tokenExpiration: Date?

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        guard let token = accessToken else {
            return nil
        }
        return HAuthorizationHeader(key: "Authorization", value: "Bearer \(token)")
    }

    private static let logger = LogBird(subsystem: "com.harbor.example", category: "Auth")

    func authFailed() async {
        // Handle auth failure - e.g., refresh token or show login
        Self.logger.log("Authentication failed!", level: .error)
    }

    func setToken(_ token: String, expiresIn: TimeInterval) {
        self.accessToken = token
        self.tokenExpiration = Date().addingTimeInterval(expiresIn)
    }

    func clearToken() {
        self.accessToken = nil
        self.tokenExpiration = nil
    }
}



/// Custom authentication with token refresh and retry logic
final class CustomAuthProvider: HAuthProviderProtocol, @unchecked Sendable {
    private var token: String?
    private var expiresAt: Date?

    private let baseURL: String

    init(baseURL: String = "https://api.example.com") {
        self.baseURL = baseURL
    }

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        guard let token = token else {
            return nil
        }

        return HAuthorizationHeader(
            key: "Authorization",
            value: "Bearer \(token)"
        )
    }

    private static let logger = LogBird(subsystem: "com.harbor.example", category: "Auth")

    func authFailed() async {
        // Try to refresh the token
        do {
            try await refreshTokenInternal()
        } catch {
            Self.logger.log("Auth refresh failed", error: error, level: .error)
        }
    }

    private func refreshTokenInternal() async throws {

        // Simulate refresh token request
        // In production, this would be an actual network request
        let newToken = "new_access_token_\(UUID().uuidString)"
        self.token = newToken
        self.expiresAt = Date().addingTimeInterval(3600)
    }

    func login(email: String, password: String) async throws {
        // Simulate login
        self.token = "access_token_\(UUID().uuidString)"
        self.expiresAt = Date().addingTimeInterval(3600)
    }

    func logout() async {
        self.token = nil
        self.expiresAt = nil

        // Clear auth provider from Harbor
        await Harbor.setAuthProvider(nil)
    }
}


// MARK: - Token Refresh Demo

/// Token the demo auth provider starts with; the demo stub server rejects it.
private let expiredDemoToken = "expired_demo_token"
/// Token the provider gets by refreshing; the demo stub server accepts it.
private let validDemoToken = "valid_demo_token"

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
/// `authFailed()`.
final class RefreshingAuthProvider: HAuthProviderProtocol, @unchecked Sendable {
    private var accessToken = expiredDemoToken
    private(set) var refreshCount = 0

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        HAuthorizationHeader(key: "Authorization", value: "Bearer \(accessToken)")
    }

    private static let logger = LogBird(subsystem: "com.harbor.example", category: "Auth")

    func authFailed() async {
        // Called once per request after a 401 that the current header cannot recover from.
        // A real provider would call its token endpoint here (or log the user out).
        Self.logger.log("Server rejected the access token; refreshing it", level: .info)
        accessToken = validDemoToken
        refreshCount += 1
    }

    /// Restores the initial state so the demo can run again with an expired token.
    func reset() {
        accessToken = expiredDemoToken
        refreshCount = 0
    }
}

/// Local stub server for the token-refresh demo.
///
/// Installed in the `protocolClasses` of the demo's custom `URLSession`, it answers requests
/// to `auth-demo.local` without touching the network: the expired demo token gets a 401 and
/// the refreshed token gets a 200 with a small JSON body. Requests to any other host are
/// untouched.
final class AuthDemoStubProtocol: URLProtocol {
    static let host = "auth-demo.local"

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let statusCode = authorization == "Bearer \(validDemoToken)" ? 200 : 401

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = statusCode == 200
            ? "{\"message\": \"Secure data unlocked\"}"
            : "{\"message\": \"Invalid or expired token\"}"
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
