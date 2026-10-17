//
//  RequestsView+Basic.swift
//  HarborExample
//
//  Basic GET requests
//

import SwiftUI
import HarborJRPC
import HarborWebSocket
import Harbor
import LogBird

// MARK: - Basic GET requests
extension RequestsView {
    func performBasicGet() {
        Self.logger.log("performBasicGet called", level: .info)
        addResult("=== GET - Basic Request ===")
        performWithLoading {
            let response = await GetUsersRequest().request()
            await MainActor.run {
                switch response {
                case .success(let users):
                    addResult("Success! Got \(users.count) users")
                    if let first = users.first {
                        addResult("First user: \(first.name) (\(first.email))")
                    }
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performGetWithPathParameter() {
        addResult("=== GET - Path Parameter ===")
        performWithLoading {
            let response = await GetUserRequest(userId: 1).request()
            await MainActor.run {
                switch response {
                case .success(let user):
                    addResult("User: \(user.name)")
                    addResult("Email: \(user.email)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performGetWithQueryParams() {
        addResult("=== GET - Query Parameters ===")
        performWithLoading {
            let response = await SearchUsersRequest(username: "Bret").request()
            await MainActor.run {
                switch response {
                case .success(let users):
                    addResult("Found \(users.count) user(s) with username Bret")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
