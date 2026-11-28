//
//  HImageMock.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// A canned answer for an image URL, for SwiftUI previews and tests. Register it with
/// `HarborImage.register(_:)`. Mocks are served in debug builds only (never in release, whatever
/// `HarborImage.setMocksEnabled(_:)` says). A mocked load skips the disk cache, the connectivity
/// check and the network (auth, retries, download limits), is never written to disk, and
/// reports `.local` as its source; its decoded image is kept in memory like any other.
///
/// ```swift
/// await HarborImage.register(HImageMock(url: "https://cdn.example.com/a.png", data: previewPNG))
/// await HarborImage.register(HImageMock(url: "https://cdn.example.com/missing.png", error: .api(statusCode: 404)))
/// ```
public struct HImageMock: Sendable {
    /// The URL answered, compared with the composed URL of the request.
    public let url: String
    /// The bytes served, or `nil` to fail with `error`.
    public let data: Data?
    /// The error returned when `data` is `nil` (unused by a mock that serves bytes).
    public let error: HImageError
    /// How long the mock waits before answering, in seconds.
    public let delay: TimeInterval

    /// Creates a mock that serves bytes.
    /// - Parameters:
    ///   - url: The URL answered.
    ///   - data: The image bytes.
    ///   - delay: How long to wait before answering, in seconds. Default: 0.
    public init(url: String, data: Data, delay: TimeInterval = 0) {
        self.url = url
        self.data = data
        self.error = .notAnImage
        self.delay = delay
    }

    /// Creates a mock that fails.
    /// - Parameters:
    ///   - url: The URL answered.
    ///   - error: The error returned.
    ///   - delay: How long to wait before answering, in seconds. Default: 0.
    public init(url: String, error: HImageError, delay: TimeInterval = 0) {
        self.url = url
        self.data = nil
        self.error = error
        self.delay = delay
    }
}
