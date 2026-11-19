//
//  AuthDemoStubProtocol.swift
//  HarborExample
//
//  Local stub server for the token-refresh demo
//

import Foundation

/// Local stub server for the token-refresh demo.
///
/// Installed in the `protocolClasses` of the demo's custom `URLSession`, it answers requests
/// to `auth-demo.local` without touching the network: the expired demo token gets a 401 and
/// the refreshed token gets a 200 with a small JSON body. Requests to any other host are
/// untouched.
final class AuthDemoStubProtocol: URLProtocol {
    static let host = "auth-demo.local"
    /// Token `RefreshingAuthProvider` starts with; the stub server rejects it.
    static let expiredToken = "expired_demo_token"
    /// Token `RefreshingAuthProvider` gets by refreshing; the stub server accepts it.
    static let validToken = "valid_demo_token"

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
        let statusCode = authorization == "Bearer \(Self.validToken)" ? 200 : 401

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
