//
//  CachingSection.swift
//  HarborExample
//
//  Custom cache, URLCache with ETags, cache-only reads and clearing.
//

import SwiftUI
import Harbor

struct CachingSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    var body: some View {
        ExampleSection(title: "Caching") {
            ExampleButton(title: "GET - With Custom Cache", icon: "externaldrive") { performCachedRequest() }
            ExampleButton(title: "GET - With URLCache (ETags)", icon: "network") { performURLCacheRequest() }
            ExampleButton(title: "GET - Cache Only", icon: "internaldrive") { performCacheOnlyRequest() }
            ExampleButton(title: "Clear All Cache", icon: "xmark.circle", isDestructive: true) { clearAllCache() }
        }
    }

    // MARK: - Actions

    private func performCachedRequest() {
        runner.log("=== GET - Custom Cache ===")
        runner.run {
            let response = await GetUserProfileRequest(userId: 1).request()

            await MainActor.run {
                switch response {
                case .success(let user):
                    runner.log("Cached user: \(user.name)")
                case .error(let error):
                    runner.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func performURLCacheRequest() {
        runner.log("=== GET - URLCache ===")
        runner.run {
            let response = await GetPostsRequest().request()

            await MainActor.run {
                switch response {
                case .success(let posts):
                    runner.log("Got \(posts.count) posts (with ETag support)")
                case .error(let error):
                    runner.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func performCacheOnlyRequest() {
        runner.log("=== GET - Cache Only ===")
        runner.run {
            // Reads the entry of "GET - With Custom Cache" without touching the network.
            let request = GetUserProfileRequest(userId: 1)
            let cachedUser = await request.cache()
            let eTag = await request.cachedETag()
            await MainActor.run {
                if let user = cachedUser {
                    runner.log("Successfully read from cache: \(user.name)")
                    runner.log("Cached ETag: \(eTag ?? "none")")
                } else {
                    runner.log("Cache miss (run \"GET - With Custom Cache\" first to populate it)")
                }
            }
        }
    }

    private func clearAllCache() {
        runner.log("=== Clearing Cache ===")
        runner.run {
            await Harbor.clearAllCache()
            await MainActor.run {
                runner.log("All cache cleared!")
            }
        }
    }
}
