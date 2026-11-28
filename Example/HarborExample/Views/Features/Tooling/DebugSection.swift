//
//  DebugSection.swift
//  HarborExample
//
//  `HDebugRequestProtocol`: logs the request and the response.
//

import SwiftUI
import Harbor

struct DebugSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    var body: some View {
        ExampleSection(title: "Debug Mode") {
            ExampleButton(title: "GET - Debug Mode", icon: "antenna.radiowaves.left.and.right") { performDebugRequest() }
        }
    }

    // MARK: - Actions

    private func performDebugRequest() {
        runner.log("=== Debug Request ===")
        runner.run {
            let response = await DebugGetUsersRequest().request()

            await MainActor.run {
                switch response {
                case .success(let users):
                    runner.log("Debug: Got \(users.count) users")
                case .error(let error):
                    runner.log("Debug Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
