//
//  CustomHeadersSection.swift
//  HarborExample
//
//  Per-request custom headers.
//

import SwiftUI
import Harbor

struct CustomHeadersSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    var body: some View {
        ExampleSection(title: "Custom Headers") {
            ExampleButton(title: "GET - Custom Headers", icon: "header") { performRequestWithHeaders() }
        }
    }

    // MARK: - Actions

    private func performRequestWithHeaders() {
        runner.log("=== GET - Custom Headers ===")
        runner.run {
            let response = await GetDataWithHeadersRequest().request()

            await MainActor.run {
                switch response {
                case .success(let users):
                    runner.log("Got \(users.count) users (with custom headers)")
                case .error(let error):
                    runner.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
