//
//  HImageResult.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// A loaded image: the decoded (and processed) pixels, its bytes and where it came from.
public struct HImageResult: Sendable {
    /// The decoded image after the request's processors; the first frame of an animated image.
    public let image: CGImage
    /// The image bytes: encoded with the request's `encoding` when it has one; otherwise the
    /// original bytes when there are no processors or the image is animated or an SVG, and a
    /// PNG of the processed image in any other case.
    public let data: Data
    /// The format of `data`: the original format, the encoding's format when the request has
    /// one, or `.png` for a processed still image without one.
    public let format: HImageFormat
    /// Where the image came from.
    public let source: HImageSource
    /// The frames of an animated image (GIF, APNG, animated WebP), `nil` for a still image.
    public let animation: HImageAnimation?

    /// Creates a result.
    /// - Parameters:
    ///   - image: The decoded image.
    ///   - data: The image bytes.
    ///   - format: The format of `data`.
    ///   - source: Where the image came from.
    ///   - animation: The frames of an animated image.
    public init(image: CGImage, data: Data, format: HImageFormat, source: HImageSource, animation: HImageAnimation? = nil) {
        self.image = image
        self.data = data
        self.format = format
        self.source = source
        self.animation = animation
    }

    /// The size of `image` in pixels.
    public var pixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }
}

// MARK: - Source

extension HImageResult {
    /// The same result, reported as coming from another source.
    /// - Parameter source: The new source.
    func with(source: HImageSource) -> HImageResult {
        HImageResult(image: image, data: data, format: format, source: source, animation: animation)
    }
}
