//
//  RequestsView+Auth.swift
//  HarborExample
//
//  Authentication, headers and retry requests
//

import SwiftUI
import Harbor

// MARK: - Authentication, headers and retry requests
extension RequestsView {
    func performAuthenticatedRequest() {
        addResult("=== GET - Authenticated ===")
        // Read the @State provider on the main actor before handing it to the task.
        let authProvider = authProvider
        performWithLoading {
            await authProvider.setToken("demo_token_123", expiresIn: 3600)
            await Harbor.setAuthProvider(authProvider)

            let response = await GetPrivateDataRequest().request()

            await MainActor.run {
                switch response {
                case .success(let user):
                    addResult("Authenticated user: \(user.name)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performAuthWithRefresh() {
        addResult("=== Auth with Token Refresh ===")
        // Read the @State provider on the main actor before handing it to the task.
        let refreshAuthProvider = refreshAuthProvider
        performWithLoading {
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
                    addResult("Server rejected the expired token with 401")
                    addResult("authFailed() refreshed the token \(refreshCount)x; Harbor re-sent the request")
                    addResult("Retry succeeded: \(data.message)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Headers

    func performRequestWithHeaders() {
        addResult("=== GET - Custom Headers ===")
        performWithLoading {
            let response = await GetDataWithHeadersRequest().request()

            await MainActor.run {
                switch response {
                case .success(let users):
                    addResult("Got \(users.count) users (with custom headers)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Retry

    func performRequestWithRetry() {
        addResult("=== GET - With Retry ===")
        performWithLoading {
            let response = await GetUnreliableDataRequest().request()

            await MainActor.run {
                switch response {
                case .success(let users):
                    addResult("Got \(users.count) users (after retries)")
                case .error(let error):
                    addResult("Error after retries: \(error.localizedDescription)")
                }
            }
        }
    }
}
