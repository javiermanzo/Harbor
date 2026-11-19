//
//  RequestsView+Streaming.swift
//  HarborExample
//
//  Streaming and pagination requests
//

import SwiftUI
import Harbor

// MARK: - Streaming and pagination requests
extension RequestsView {
    func performStreamRequest() {
        addResult("=== Stream - Cache + Remote ===")
        performWithLoading {
            do {
                // First populate cache
                _ = await GetUserRequest(userId: 1).request()

                // Now stream
                for try await (user, origin) in GetUserRequest(userId: 1).requestStream(source: .cacheAndRemote) {
                    let source = origin == .cache ? "CACHE" : "REMOTE"
                    await MainActor.run {
                        addResult("[\(source)] User: \(user.name)")
                    }
                }
            } catch {
                await MainActor.run {
                    addResult("Stream error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performStreamCacheOnlyRequest() {
        addResult("=== Stream - Cache Only ===")
        performWithLoading {
            do {
                for try await (user, origin) in GetUserRequest(userId: 1).requestStream(source: .cacheOnly) {
                    let source = origin == .cache ? "CACHE" : "REMOTE"
                    await MainActor.run {
                        addResult("[\(source)] User: \(user.name)")
                    }
                }
            } catch {
                await MainActor.run {
                    if case HRequestError.noCachedDataFound = error {
                        addResult("Error: \(error.localizedDescription) (run \"Stream - Cache + Remote\" first to populate the cache)")
                    } else {
                        addResult("Stream error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func performStreamRemoteOnlyRequest() {
        addResult("=== Stream - Remote Only ===")
        performWithLoading {
            do {
                for try await (user, origin) in GetUserRequest(userId: 1).requestStream(source: .remoteOnly) {
                    let source = origin == .cache ? "CACHE" : "REMOTE"
                    await MainActor.run {
                        addResult("[\(source)] User: \(user.name)")
                    }
                }
            } catch {
                await MainActor.run {
                    addResult("Stream error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Pagination

    func performPaginatedRequest() {
        addResult("=== GET - Paginated ===")
        performWithLoading {
            let response = await GetPaginatedPostsRequest(page: 1, limit: 5).request()

            await MainActor.run {
                switch response {
                case .success(let posts):
                    addResult("Got \(posts.count) posts (page 1)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
