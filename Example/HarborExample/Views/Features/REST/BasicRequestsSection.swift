//
//  BasicRequestsSection.swift
//  HarborExample
//
//  GET requests: plain, path parameter and query parameters.
//

import SwiftUI
import Harbor
import LogBird

struct BasicRequestsSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    private static let logger = LogBird(subsystem: "com.harbor.example", category: "BasicRequestsSection")

    var body: some View {
        ExampleSection(title: "Basic GET Requests") {
            ExampleButton(title: "GET - Simple Request", icon: "arrow.down.circle") { performBasicGet() }
            ExampleButton(title: "GET - With Path Parameter", icon: "arrow.right.circle") { performGetWithPathParameter() }
            ExampleButton(title: "GET - With Query Params", icon: "magnifyingglass") { performGetWithQueryParams() }
        }
    }

    // MARK: - Actions

    private func performBasicGet() {
        Self.logger.log("performBasicGet called", level: .info)
        runner.log("=== GET - Basic Request ===")
        runner.run {
            let response = await GetUsersRequest().request()
            await MainActor.run {
                switch response {
                case .success(let users):
                    runner.log("Success! Got \(users.count) users")
                    if let first = users.first {
                        runner.log("First user: \(first.name) (\(first.email))")
                    }
                case .error(let error):
                    runner.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func performGetWithPathParameter() {
        runner.log("=== GET - Path Parameter ===")
        runner.run {
            let response = await GetUserRequest(userId: 1).request()
            await MainActor.run {
                switch response {
                case .success(let user):
                    runner.log("User: \(user.name)")
                    runner.log("Email: \(user.email)")
                case .error(let error):
                    runner.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func performGetWithQueryParams() {
        runner.log("=== GET - Query Parameters ===")
        runner.run {
            let response = await SearchUsersRequest(username: "Bret").request()
            await MainActor.run {
                switch response {
                case .success(let users):
                    runner.log("Found \(users.count) user(s) with username Bret")
                case .error(let error):
                    runner.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
