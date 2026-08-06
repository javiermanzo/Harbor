//
//  AuthExamples.swift
//  HarborExample
//
//  Authentication provider examples for Harbor
//

import Foundation
import Harbor
import LogBird

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
    private var refreshToken: String?
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
        guard let refreshToken = refreshToken else {
            throw AuthError.noRefreshToken
        }

        // Simulate refresh token request
        // In production, this would be an actual network request
        let newToken = "new_access_token_\(UUID().uuidString)"
        self.token = newToken
        self.expiresAt = Date().addingTimeInterval(3600)
    }

    func login(email: String, password: String) async throws {
        // Simulate login
        self.token = "access_token_\(UUID().uuidString)"
        self.refreshToken = "refresh_token_\(UUID().uuidString)"
        self.expiresAt = Date().addingTimeInterval(3600)
    }

    func logout() async {
        self.token = nil
        self.refreshToken = nil
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
/// It starts holding an expired access token. The demo stub server rejects that token
/// with a 401 and Harbor asks for the authorization header again before retrying the
/// request. Being asked again for the same token is the signal that the server rejected
/// it, so the provider refreshes the token and Harbor's automatic retry succeeds.
final class RefreshingAuthProvider: HAuthProviderProtocol, @unchecked Sendable {
    private var accessToken = expiredDemoToken
    private var currentTokenWasSent = false
    private(set) var refreshCount = 0

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        if currentTokenWasSent {
            refreshAccessToken()
        }
        currentTokenWasSent = true
        return HAuthorizationHeader(key: "Authorization", value: "Bearer \(accessToken)")
    }

    private static let logger = LogBird(subsystem: "com.harbor.example", category: "Auth")

    func authFailed() async {
        // Called when Harbor cannot recover the request with a refreshed token.
        Self.logger.log("Authentication failed: no fresh token available", level: .error)
    }

    private func refreshAccessToken() {
        // A real provider would call its token endpoint here.
        accessToken = validDemoToken
        refreshCount += 1
    }

    /// Restores the initial state so the demo can run again with an expired token.
    func reset() {
        accessToken = expiredDemoToken
        currentTokenWasSent = false
        refreshCount = 0
    }
}

/// Local stub server for the token-refresh demo.
///
/// Registered as a global URLProtocol, it answers requests to `auth-demo.local`
/// without touching the network: the expired demo token gets a 401 and the refreshed
/// token gets a 200 with a small JSON body. Requests to any other host are untouched.
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
