//
//  RequestsView+Caching.swift
//  HarborExample
//
//  Caching requests
//

import SwiftUI
import Harbor

// MARK: - Caching requests
extension RequestsView {
    func performCachedRequest() {
        addResult("=== GET - Custom Cache ===")
        performWithLoading {
            let response = await GetUserProfileRequest(userId: 1).request()

            await MainActor.run {
                switch response {
                case .success(let user):
                    addResult("Cached user: \(user.name)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performURLCacheRequest() {
        addResult("=== GET - URLCache ===")
        performWithLoading {
            let response = await GetPostsRequest().request()

            await MainActor.run {
                switch response {
                case .success(let posts):
                    addResult("Got \(posts.count) posts (with ETag support)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performCacheOnlyRequest() {
        addResult("=== GET - Cache Only ===")
        performWithLoading {
            // Reads the entry of "GET - With Custom Cache" without touching the network.
            let request = GetUserProfileRequest(userId: 1)
            let cachedUser = await request.cache()
            let eTag = await request.cachedETag()
            await MainActor.run {
                if let user = cachedUser {
                    addResult("Successfully read from cache: \(user.name)")
                    addResult("Cached ETag: \(eTag ?? "none")")
                } else {
                    addResult("Cache miss (run \"GET - With Custom Cache\" first to populate it)")
                }
            }
        }
    }


    func clearAllCache() {
        addResult("=== Clearing Cache ===")
        performWithLoading {
            await Harbor.clearAllCache()
            await MainActor.run {
                addResult("All cache cleared!")
            }
        }
    }
}
