//
//  HImageTargetSize.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// The size an image is decoded at, in pixels (downsampling). A raster image is never decoded
/// larger than its own size; an SVG is rendered at the target size, enlarged if needed. The
/// size is compared with the image as displayed, after its EXIF orientation.
public struct HImageTargetSize: Sendable, Hashable {
    /// How the image is scaled to the target size; the aspect ratio is always kept.
    public enum ContentMode: String, Sendable, Hashable {
        /// The whole image fits inside the target size.
        case fit
        /// The image covers the target size; one side may be larger.
        case fill
    }

    /// The target width in pixels, at least 1.
    public let pixelWidth: Int
    /// The target height in pixels, at least 1.
    public let pixelHeight: Int
    /// How the image is scaled to the target size.
    public let contentMode: ContentMode

    /// Creates a target size in pixels. Values below 1 are clamped to 1.
    /// - Parameters:
    ///   - pixelWidth: The target width in pixels.
    ///   - pixelHeight: The target height in pixels.
    ///   - contentMode: How the image is scaled to the target size. Default: `.fill`.
    public init(pixelWidth: Int, pixelHeight: Int, contentMode: ContentMode = .fill) {
        self.pixelWidth = max(1, pixelWidth)
        self.pixelHeight = max(1, pixelHeight)
        self.contentMode = contentMode
    }

    /// Creates a target size from a size in points and the display scale. Pixel lengths are
    /// rounded up, within `1...100_000`.
    /// - Parameters:
    ///   - size: The size the image is displayed at, in points.
    ///   - scale: The display scale (`@Environment(\.displayScale)`).
    ///   - contentMode: How the image is scaled to the target size. Default: `.fill`.
    public init(size: CGSize, scale: CGFloat, contentMode: ContentMode = .fill) {
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        self.init(pixelWidth: Self.pixels(size.width * safeScale),
                  pixelHeight: Self.pixels(size.height * safeScale),
                  contentMode: contentMode)
    }
}

// MARK: - Scaling

extension HImageTargetSize {
    /// The scale factor (at most 1) that brings an image of the given size to the target.
    /// - Parameter imageSize: The image size in pixels.
    func scaleFactor(for imageSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let widthRatio = CGFloat(pixelWidth) / imageSize.width
        let heightRatio = CGFloat(pixelHeight) / imageSize.height
        let factor = contentMode == .fit ? min(widthRatio, heightRatio) : max(widthRatio, heightRatio)
        return min(1, factor)
    }

    /// The identifier of the target in cache keys.
    var identifier: String {
        "\(pixelWidth)x\(pixelHeight)-\(contentMode.rawValue)"
    }

    /// Rounds a pixel length up to a whole value in `1...100_000`.
    /// - Parameter value: The length in pixels.
    private static func pixels(_ value: CGFloat) -> Int {
        guard value.isFinite else { return 1 }
        return Int(min(max(value.rounded(.up), 1), 100_000))
    }
}
