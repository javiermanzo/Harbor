//
//  DirectCallsSection.swift
//  HarborExample
//
//  `HarborImage` calls without a view: progress callback, `AsyncStream` of events, original bytes and compression.
//

import SwiftUI
import HarborImage

struct DirectCallsSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    @State private var directImage: CGImage?
    @State private var directProgress: Double?
    @State private var directTask: Task<Void, Never>?

    var body: some View {
        ExampleSection(title: "Direct calls (no view)") {
            if let directImage {
                Image(decorative: directImage, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
            }
            if let directProgress {
                ProgressView(value: directProgress)
            }
            ExampleButton(title: "Load with progress callback", icon: "arrow.down.circle") { loadWithCallbacks() }
            ExampleButton(title: "Cancel load", icon: "xmark.circle", isDestructive: true) {
                directTask?.cancel()
            }
            ExampleButton(title: "Events as an AsyncStream", icon: "dot.radiowaves.left.and.right") { streamEvents() }
            ExampleButton(title: "Original bytes (data)", icon: "doc.zipper") { loadOriginalBytes() }
            ExampleButton(title: "async + compress to 50 KB", icon: "arrow.down.right.and.arrow.up.left") { loadAndCompress() }
        }
    }

    // MARK: - Actions

    /// `HarborImage.image(for:onEvent:)` with the optional progress callback (main actor).
    /// Cancelling the task cancels the load.
    private func loadWithCallbacks() {
        directImage = nil
        directProgress = 0
        let request = HImageRequest(url: "https://picsum.photos/id/\(Int.random(in: 50...200))/1600/1200",
                                    cachePolicy: .reloadIgnoringCache)
        directTask = Task { @Sendable in
            let response = await HarborImage.image(for: request, onEvent: { event in
                if case .progress(let fraction) = event { directProgress = fraction }
            })
            await MainActor.run {
                directProgress = nil
                switch response {
                case .success(let result):
                    directImage = result.image
                    runner.log("image: \(result.image.width)x\(result.image.height) from \(result.source.rawValue)")
                case .failure(let error):
                    runner.log("image failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// `HarborImage.events(for:)`: the same events as the callback, as an `AsyncStream`.
    private func streamEvents() {
        let request = HImageRequest(url: "https://picsum.photos/id/\(Int.random(in: 200...300))/800/600",
                                    cachePolicy: .reloadIgnoringCache)
        Task { @Sendable in
            for await event in HarborImage.events(for: request) {
                let line: String
                switch event {
                case .started: line = "event: started"
                case .progress(let fraction): line = "event: progress \(Int(fraction * 100))%"
                case .retrying(let attempt): line = "event: retrying (\(attempt))"
                case .loaded(let source): line = "event: loaded from \(source.rawValue)"
                case .finished(let response): line = "event: finished (\(response.error == nil ? "success" : "failure"))"
                }
                await MainActor.run { runner.log(line) }
            }
        }
    }

    /// `HarborImage.data(for:)`: the original bytes, neither decoded nor processed.
    private func loadOriginalBytes() {
        let request = HImageRequest(url: ImageDemo.photos[4])
        Task { @Sendable in
            let message: String
            switch await HarborImage.data(for: request) {
            case .success(let data, let format, let source):
                message = "data: \(data.count / 1024) KB \(format.rawValue) from \(source.rawValue)"
            case .failure(let error):
                message = "data failed: \(error.localizedDescription)"
            }
            await MainActor.run { runner.log(message) }
        }
    }

    /// `HarborImage.image(for:)` with async/await, then compression without downloading again.
    private func loadAndCompress() {
        let url = ImageDemo.photos[3]
        Task { @Sendable in
            let response = await HarborImage.image(for: HImageRequest(url: url))
            guard let image = response.result?.image else {
                await MainActor.run { runner.log("image failed: \(response.error?.localizedDescription ?? "")") }
                return
            }
            let message: String
            do {
                let data = try await HarborImage.encode(image, as: .jpeg(quality: 0.9, maxBytes: 50_000))
                message = "JPEG under 50 KB: \(data.count) bytes"
            } catch {
                message = "encode failed: \(error.localizedDescription)"
            }
            await MainActor.run { runner.log(message) }
        }
    }
}
