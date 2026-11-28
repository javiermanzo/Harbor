//
//  RetrySection.swift
//  HarborExample
//
//  `HRetryPolicy` against an unreliable endpoint.
//

import SwiftUI
import Harbor

struct RetrySection: View {
    @EnvironmentObject private var runner: ExampleRunner

    var body: some View {
        ExampleSection(title: "Retry Logic") {
            ExampleButton(title: "GET - With Retry (3x)", icon: "arrow.clockwise.circle") { performRequestWithRetry() }
        }
    }

    // MARK: - Actions

    private func performRequestWithRetry() {
        runner.log("=== GET - With Retry ===")
        runner.run {
            let response = await GetUnreliableDataRequest().request()

            await MainActor.run {
                switch response {
                case .success(let users):
                    runner.log("Got \(users.count) users (after retries)")
                case .error(let error):
                    runner.log("Error after retries: \(error.localizedDescription)")
                }
            }
        }
    }
}
