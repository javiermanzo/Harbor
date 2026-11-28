//
//  HImagePrefetcher.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// Loads images ahead of time, a few at once and at low priority, so they are cached by the
/// time they are shown (the next page of a feed, the images of the next screen).
///
/// ```swift
/// let prefetcher = HImagePrefetcher(maxConcurrent: 3)
/// let report = await prefetcher.prefetch(upcoming.map { HImageRequest(url: $0) })
/// await prefetcher.start(more)   // without waiting
/// await prefetcher.cancel()      // stops what start(_:) launched
/// ```
@HRequestManagerActor
public final class HImagePrefetcher {
    /// What prefetching warms up.
    public enum Destination: String, Sendable, Hashable {
        /// The original bytes on disk only; nothing is decoded (default, cheapest).
        case disk
        /// The decoded, processed image in memory too, ready for the first render.
        case memoryAndDisk
    }

    /// How many images load at once.
    public let maxConcurrent: Int
    /// What prefetching warms up.
    public let destination: Destination
    /// The prefetches started with `start(_:)`, by id.
    private var running: [UInt64: Task<Void, Never>] = [:]
    /// The next prefetch id.
    private var nextID: UInt64 = 0

    /// Creates a prefetcher.
    /// - Parameters:
    ///   - maxConcurrent: How many images load at once. Default: 3. Values below 1 are clamped to 1.
    ///   - destination: What prefetching warms up. Default: `.disk`.
    public nonisolated init(maxConcurrent: Int = 3, destination: Destination = .disk) {
        self.maxConcurrent = max(1, maxConcurrent)
        self.destination = destination
    }
}

// MARK: - Prefetching

public extension HImagePrefetcher {
    /// Loads the images and waits for them. Cancelling the calling task stops the pending ones.
    /// - Parameter requests: The images.
    /// - Returns: How many were loaded, failed or were cancelled.
    @discardableResult
    func prefetch(_ requests: [any HImageRequestProtocol]) async -> HImagePrefetchReport {
        let destination = destination
        var report = HImagePrefetchReport()
        await withTaskGroup(of: HImageError?.self) { group in
            var pending = requests.makeIterator()
            func addNext() -> Bool {
                guard let request = pending.next() else { return false }
                group.addTask(priority: .utility) {
                    await Self.load(request, destination: destination)
                }
                return true
            }
            for _ in 0..<maxConcurrent where !addNext() { break }
            for await error in group {
                report.record(error)
                _ = addNext()
            }
        }
        return report
    }

    /// Starts loading the images without waiting; `cancel()` stops them.
    /// - Parameter requests: The images.
    func start(_ requests: [any HImageRequestProtocol]) {
        let id = nextID
        nextID &+= 1
        running[id] = Task(priority: .utility) {
            await prefetch(requests)
            running[id] = nil
        }
    }

    /// Cancels the prefetches started with `start(_:)`. Loads of the same images by visible
    /// views are not affected.
    func cancel() {
        running.values.forEach { $0.cancel() }
        running.removeAll()
    }
}

// MARK: - Loading

extension HImagePrefetcher {
    /// Loads one image.
    /// - Parameters:
    ///   - request: The image.
    ///   - destination: What is warmed up.
    /// - Returns: The error, or `nil` on success.
    private static func load(_ request: any HImageRequestProtocol, destination: Destination) async -> HImageError? {
        switch destination {
        case .disk:
            return await HarborImage.data(for: request).error
        case .memoryAndDisk:
            return await HarborImage.image(for: request).error
        }
    }
}

// MARK: - Convenience

public extension HarborImage {
    /// Loads images ahead of time with a default prefetcher (3 at once, to disk).
    /// - Parameter requests: The images.
    /// - Returns: How many were loaded, failed or were cancelled.
    @discardableResult
    static func prefetch(_ requests: [any HImageRequestProtocol]) async -> HImagePrefetchReport {
        await HImagePrefetcher().prefetch(requests)
    }
}
