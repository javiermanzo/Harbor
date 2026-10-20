//
//  RequestsView+Writes.swift
//  HarborExample
//
//  POST, PUT, PATCH and DELETE requests
//

import SwiftUI
import HarborJRPC
import HarborWebSocket
import Harbor
import LogBird

// MARK: - POST, PUT, PATCH and DELETE requests
extension RequestsView {
    func performPostRequest() {
        addResult("=== POST - Create Resource ===")
        performWithLoading {
            // The type annotation selects the model-returning `request()` overload.
            let response: HResponseWithResult<Post> = await CreatePostRequest(
                title: "My New Post",
                body: "This is the body of my post",
                userId: 1
            ).request()

            await MainActor.run {
                switch response {
                case .success(let post):
                    addResult("Post created successfully! Server assigned id \(post.id)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performRawBodyPost() {
        addResult("=== POST - Encodable rawBody ===")
        performWithLoading {
            // `rawBody` sends the pre-encoded model as-is with `Content-Type: application/json`.
            let post = Post(id: 0, userId: 1, title: "Encoded with JSONEncoder", body: "Sent through rawBody")
            let response: HResponseWithResult<Post> = await CreatePostWithModelRequest(post: post).request()

            await MainActor.run {
                switch response {
                case .success(let created):
                    addResult("Post created from an Encodable model! Server assigned id \(created.id)")
                    addResult("Title echoed by the server: \(created.title)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performMultipartPost() {
        addResult("=== POST - Multipart ===")
        performWithLoading {
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
                    addResult("Upload successful!")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - PUT & PATCH

    func performPutRequest() {
        addResult("=== PUT - Full Update ===")
        performWithLoading {
            let response: HResponseWithResult<Post> = await UpdatePostRequest(
                postId: 1,
                title: "Updated Title",
                body: "Updated body content",
                userId: 1
            ).request()

            await MainActor.run {
                switch response {
                case .success(let post):
                    addResult("Post updated successfully! New title: \(post.title)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performPatchRequest() {
        addResult("=== PATCH - Partial Update ===")
        performWithLoading {
            let response: HResponseWithResult<Post> = await PatchPostRequest(
                postId: 1,
                title: "Just the Title"
            ).request()

            await MainActor.run {
                switch response {
                case .success(let post):
                    addResult("Post patched successfully! Title: \(post.title) (body kept: \(post.body.count) chars)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - DELETE

    func performDeleteRequest() {
        addResult("=== DELETE - Remove Resource ===")
        performWithLoading {
            let response = await DeletePostRequest(postId: 1).request()

            await MainActor.run {
                switch response {
                case .success:
                    addResult("Post deleted successfully!")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
