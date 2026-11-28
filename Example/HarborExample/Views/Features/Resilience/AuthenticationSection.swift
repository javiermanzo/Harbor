//
//  AuthenticationSection.swift
//  HarborExample
//
//  Authenticated requests and the `401` token refresh flow.
//

import SwiftUI
import Harbor

struct AuthenticationSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    // Auth providers are actors (not `ObservableObject`s), so `@State` keeps one instance alive
    // across SwiftUI render passes.
    /// Auth provider for authenticated requests
    @State private var authProvider = TokenAuthProvider()
    /// Auth provider for the token-refresh demo (starts with an expired token)
    @State private var refreshAuthProvider = RefreshingAuthProvider()

    var body: some View {
        ExampleSection(title: "Authentication") {
            ExampleButton(title: "GET - With Auth", icon: "lock.shield") { performAuthenticatedRequest() }
            ExampleButton(title: "GET - Auth with Token Refresh", icon: "lock.rotation") { performAuthWithRefresh() }
        }
    }

    // MARK: - Actions

    private func performAuthenticatedRequest() {
        runner.log("=== GET - Authenticated ===")
        // Read the @State provider on the main actor before handing it to the task.
        let authProvider = authProvider
        runner.run {
            await authProvider.setToken("demo_token_123", expiresIn: 3600)
            await Harbor.setAuthProvider(authProvider)

            let response = await GetPrivateDataRequest().request()

            await MainActor.run {
                switch response {
                case .success(let user):
                    runner.log("Authenticated user: \(user.name)")
                case .error(let error):
                    runner.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func performAuthWithRefresh() {
        runner.log("=== Auth with Token Refresh ===")
        // Read the @State provider on the main actor before handing it to the task.
        let refreshAuthProvider = refreshAuthProvider
        runner.run {
            await refreshAuthProvider.reset()

            // Route auth-demo.local through the local stub server (no real network traffic): the
            // session's `protocolClasses` inject the stub, so no global registration is required.
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [AuthDemoStubProtocol.self] + (config.protocolClasses ?? [])
            // A custom session is used as-is: Harbor's delegate keeps SSL pinning, mTLS and the
            // cross-origin redirect policy active on it.
            let delegate = await Harbor.makeURLSessionDelegate()
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            await Harbor.setCustomURLSession(session)

            // The provider starts with an expired token that the stub server rejects with a 401.
            // Harbor calls `authFailed()` once, the provider refreshes the token, and Harbor
            // re-sends the request with the new header.
            await Harbor.setAuthProvider(refreshAuthProvider)

            let response = await GetSecureDemoDataRequest().request()
            let refreshCount = await refreshAuthProvider.refreshCount

            // Restore the default Harbor sessions and release the demo session
            await Harbor.setCustomURLSession(nil)
            session.finishTasksAndInvalidate()

            await MainActor.run {
                switch response {
                case .success(let data):
                    runner.log("Server rejected the expired token with 401")
                    runner.log("authFailed() refreshed the token \(refreshCount)x; Harbor re-sent the request")
                    runner.log("Retry succeeded: \(data.message)")
                case .error(let error):
                    runner.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
