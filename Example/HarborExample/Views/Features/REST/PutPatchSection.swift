//
//  PutPatchSection.swift
//  HarborExample
//
//  PUT (full update) and PATCH (partial update) requests.
//

import SwiftUI
import Harbor

struct PutPatchSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    var body: some View {
        ExampleSection(title: "PUT & PATCH") {
            ExampleButton(title: "PUT - Full Update", icon: "arrow.triangle.2.circlepath") { performPutRequest() }
            ExampleButton(title: "PATCH - Partial Update", icon: "pencil") { performPatchRequest() }
        }
    }

    // MARK: - Actions

    private func performPutRequest() {
        runner.log("=== PUT - Full Update ===")
        runner.run {
            let response: HResponseWithResult<Post> = await UpdatePostRequest(
                postId: 1,
                title: "Updated Title",
                body: "Updated body content",
                userId: 1
            ).request()

            await MainActor.run {
                switch response {
                case .success(let post):
                    runner.log("Post updated successfully! New title: \(post.title)")
                case .error(let error):
                    runner.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func performPatchRequest() {
        runner.log("=== PATCH - Partial Update ===")
        runner.run {
            let response: HResponseWithResult<Post> = await PatchPostRequest(
                postId: 1,
                title: "Just the Title"
            ).request()

            await MainActor.run {
                switch response {
                case .success(let post):
                    runner.log("Post patched successfully! Title: \(post.title) (body kept: \(post.body.count) chars)")
                case .error(let error):
                    runner.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
