//
//  HOverlayProcessor.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// Draws another image on top: a watermark, a badge, a play icon.
public struct HOverlayProcessor: HImageProcessor {
    /// The image drawn on top.
    public let overlay: CGImage
    /// Names the overlay in the cache key: give each different overlay image its own.
    public let id: String
    /// Where the overlay is placed.
    public let alignment: HImageAlignment
    /// The overlay width as a fraction of the image width (its height keeps the aspect ratio),
    /// or `nil` (also for zero, negative or non-finite values) to draw it at its own size.
    public let relativeWidth: CGFloat?
    /// The distance from the image edges, in pixels; negative values become 0.
    public let margin: CGFloat
    /// The overlay opacity, clamped to `0...1`.
    public let opacity: Double

    /// Creates an overlay processor.
    /// - Parameters:
    ///   - overlay: The image drawn on top.
    ///   - id: Names the overlay in the cache key.
    ///   - alignment: Where the overlay is placed. Default: `.bottomTrailing`.
    ///   - relativeWidth: The overlay width as a fraction of the image width. Default: `nil`, its own size.
    ///   - margin: The distance from the image edges, in pixels. Default: 0.
    ///   - opacity: The overlay opacity. Default: 1.
    public init(overlay: CGImage, id: String, alignment: HImageAlignment = .bottomTrailing, relativeWidth: CGFloat? = nil, margin: CGFloat = 0, opacity: Double = 1) {
        self.overlay = overlay
        self.id = id
        self.alignment = alignment
        self.relativeWidth = relativeWidth.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.margin = margin.isFinite ? max(0, margin) : 0
        self.opacity = opacity.isFinite ? min(max(opacity, 0), 1) : 1
    }
}

// MARK: - Factory

public extension HImageProcessor where Self == HOverlayProcessor {
    /// Draws another image on top.
    /// - Parameters:
    ///   - overlay: The image drawn on top.
    ///   - id: Names the overlay in the cache key.
    ///   - alignment: Where the overlay is placed. Default: `.bottomTrailing`.
    ///   - relativeWidth: The overlay width as a fraction of the image width. Default: `nil`, its own size.
    ///   - margin: The distance from the image edges, in pixels. Default: 0.
    ///   - opacity: The overlay opacity. Default: 1.
    static func overlay(_ overlay: CGImage, id: String, alignment: HImageAlignment = .bottomTrailing, relativeWidth: CGFloat? = nil, margin: CGFloat = 0, opacity: Double = 1) -> HOverlayProcessor {
        HOverlayProcessor(overlay: overlay, id: id, alignment: alignment, relativeWidth: relativeWidth, margin: margin, opacity: opacity)
    }
}

// MARK: - HImageProcessor

public extension HOverlayProcessor {
    /// Identifies the overlay, placement and opacity.
    var identifier: String {
        "overlay(\(id),\(alignment.rawValue),\(relativeWidth.map { "\($0)" } ?? "-"),\(margin),\(opacity))"
    }

    /// Draws the overlay.
    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        let imageSize = CGSize(width: image.width, height: image.height)
        var overlaySize = CGSize(width: overlay.width, height: overlay.height)
        if let relativeWidth {
            let width = imageSize.width * relativeWidth
            overlaySize = CGSize(width: width, height: width * overlaySize.height / max(1, overlaySize.width))
        }
        let origin = alignment.origin(of: overlaySize, in: imageSize, margin: margin)
        return try HImageCanvas.draw(width: image.width, height: image.height) { canvas in
            canvas.draw(image, in: CGRect(origin: .zero, size: imageSize))
            canvas.setAlpha(opacity)
            canvas.draw(overlay, in: HImageCanvas.flipped(CGRect(origin: origin, size: overlaySize), height: imageSize.height))
        }
    }
}
