//
//  StreamingSection.swift
//  HarborExample
//
//  `requestStream` with the cache and the remote as sources.
//

import SwiftUI
import Harbor

struct StreamingSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    var body: some View {
        ExampleSection(title: "Streaming") {
            ExampleButton(title: "Stream - Cache + Remote", icon: "arrow.triangle.2.circlepath.circle") { performStreamRequest() }
            ExampleButton(title: "Stream - Cache Only", icon: "internaldrive") { performStreamCacheOnlyRequest() }
            ExampleButton(title: "Stream - Remote Only", icon: "antenna.radiowaves.left.and.right") { performStreamRemoteOnlyRequest() }
        }
    }

    // MARK: - Actions

    private func performStreamRequest() {
        runner.log("=== Stream - Cache + Remote ===")
        runner.run {
            do {
                // First populate cache
                _ = await GetUserRequest(userId: 1).request()

                // Now stream
                for try await (user, origin) in GetUserRequest(userId: 1).requestStream(source: .cacheAndRemote) {
                    let source = origin == .cache ? "CACHE" : "REMOTE"
                    await MainActor.run {
                        runner.log("[\(source)] User: \(user.name)")
                    }
                }
            } catch {
                await MainActor.run {
                    runner.log("Stream error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func performStreamCacheOnlyRequest() {
        runner.log("=== Stream - Cache Only ===")
        runner.run {
            do {
                for try await (user, origin) in GetUserRequest(userId: 1).requestStream(source: .cacheOnly) {
                    let source = origin == .cache ? "CACHE" : "REMOTE"
                    await MainActor.run {
                        runner.log("[\(source)] User: \(user.name)")
                    }
                }
            } catch {
                await MainActor.run {
                    if case HRequestError.noCachedDataFound = error {
                        runner.log("Error: \(error.localizedDescription) (run \"Stream - Cache + Remote\" first to populate the cache)")
                    } else {
                        runner.log("Stream error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func performStreamRemoteOnlyRequest() {
        runner.log("=== Stream - Remote Only ===")
        runner.run {
            do {
                for try await (user, origin) in GetUserRequest(userId: 1).requestStream(source: .remoteOnly) {
                    let source = origin == .cache ? "CACHE" : "REMOTE"
                    await MainActor.run {
                        runner.log("[\(source)] User: \(user.name)")
                    }
                }
            } catch {
                await MainActor.run {
                    runner.log("Stream error: \(error.localizedDescription)")
                }
            }
        }
    }
}
