//
//  PostRequestsSection.swift
//  HarborExample
//
//  POST requests: JSON body, `rawBody` and multipart upload.
//

import SwiftUI
import Harbor

struct PostRequestsSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    var body: some View {
        ExampleSection(title: "POST Requests") {
            ExampleButton(title: "POST - Create Resource", icon: "plus.circle") { performPostRequest() }
            ExampleButton(title: "POST - Encodable rawBody", icon: "doc.plaintext") { performRawBodyPost() }
            ExampleButton(title: "POST - Multipart Upload", icon: "paperclip") { performMultipartPost() }
        }
    }

    // MARK: - Actions

    private func performPostRequest() {
        runner.log("=== POST - Create Resource ===")
        runner.run {
            // The type annotation selects the model-returning `request()` overload.
            let response: HResponseWithResult<Post> = await CreatePostRequest(
                title: "My New Post",
                body: "This is the body of my post",
                userId: 1
            ).request()

            await MainActor.run {
                switch response {
                case .success(let post):
                    runner.log("Post created successfully! Server assigned id \(post.id)")
                case .error(let error):
                    runner.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func performRawBodyPost() {
        runner.log("=== POST - Encodable rawBody ===")
        runner.run {
            // `rawBody` sends the pre-encoded model as-is with `Content-Type: application/json`.
            let post = Post(id: 0, userId: 1, title: "Encoded with JSONEncoder", body: "Sent through rawBody")
            let response: HResponseWithResult<Post> = await CreatePostWithModelRequest(post: post).request()

            await MainActor.run {
                switch response {
                case .success(let created):
                    runner.log("Post created from an Encodable model! Server assigned id \(created.id)")
                    runner.log("Title echoed by the server: \(created.title)")
                case .error(let error):
                    runner.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func performMultipartPost() {
        runner.log("=== POST - Multipart ===")
        runner.run {
            // Write a placeholder file: multipart file parts are read (streamed) from disk.
            let imageFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("harbor-example-image.png")
            let imageWritten = (try? Data("fake image data".utf8).write(to: imageFileURL)) != nil
            let response = await UploadPostRequest(
                title: "Post with Image",
                body: "Description",
                userId: 1,
                imageFileURL: imageWritten ? imageFileURL : nil
            ).request()

            await MainActor.run {
                switch response {
                case .success:
                    runner.log("Upload successful!")
                case .error(let error):
                    runner.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
