//
//  DeleteSection.swift
//  HarborExample
//
//  DELETE request.
//

import SwiftUI
import Harbor

struct DeleteSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    var body: some View {
        ExampleSection(title: "DELETE") {
            ExampleButton(title: "DELETE - Remove Resource", icon: "trash", isDestructive: true) { performDeleteRequest() }
        }
    }

    // MARK: - Actions

    private func performDeleteRequest() {
        runner.log("=== DELETE - Remove Resource ===")
        runner.run {
            let response = await DeletePostRequest(postId: 1).request()

            await MainActor.run {
                switch response {
                case .success:
                    runner.log("Post deleted successfully!")
                case .error(let error):
                    runner.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
