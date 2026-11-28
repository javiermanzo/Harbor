//
//  HResizeProcessor.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// Resizes the image to a size in pixels. As the first processor of a request without a
/// `targetSize`, it also downsamples while decoding, so the full-size image is never decoded.
public struct HResizeProcessor: HImageProcessor {
    /// How the image is scaled to the size.
    public enum Mode: String, Sendable, Hashable {
        /// Keeps the aspect ratio and fits inside the size; one side may be shorter.
        case fit
        /// Keeps the aspect ratio, covers the size and crops the excess around the center.
        case fill
        /// Scales to exactly the size, ignoring the aspect ratio; without `allowsUpscaling`, a
        /// side shorter than the size keeps its length.
        case stretch
    }

    /// The size in pixels, rounded to whole pixels, at least 1 and at most 65,536 per side
    /// (an infinite or not-a-number side is clamped).
    public let size: CGSize
    /// How the image is scaled to the size.
    public let mode: Mode
    /// Whether an image smaller than the size is enlarged.
    public let allowsUpscaling: Bool

    /// Creates a resize processor.
    /// - Parameters:
    ///   - size: The size in pixels.
    ///   - mode: How the image is scaled to the size. Default: `.fit`.
    ///   - allowsUpscaling: Whether a smaller image is enlarged. Default: `false`.
    public init(size: CGSize, mode: Mode = .fit, allowsUpscaling: Bool = false) {
        self.size = CGSize(width: Self.clamped(size.width), height: Self.clamped(size.height))
        self.mode = mode
        self.allowsUpscaling = allowsUpscaling
    }
}

// MARK: - Clamping

private extension HResizeProcessor {
    /// The largest side in pixels, so converting a size to `Int` never traps.
    static let maxSide: CGFloat = 65_536

    /// Rounds a side to whole pixels between 1 and `maxSide`; not-a-number becomes 1.
    static func clamped(_ side: CGFloat) -> CGFloat {
        guard !side.isNaN else { return 1 }
        return min(maxSide, max(1, side.rounded()))
    }
}

// MARK: - Factory

public extension HImageProcessor where Self == HResizeProcessor {
    /// Resizes the image to a size in pixels.
    /// - Parameters:
    ///   - size: The size in pixels.
    ///   - mode: How the image is scaled to the size. Default: `.fit`.
    ///   - allowsUpscaling: Whether a smaller image is enlarged. Default: `false`.
    static func resize(to size: CGSize, mode: HResizeProcessor.Mode = .fit, allowsUpscaling: Bool = false) -> HResizeProcessor {
        HResizeProcessor(size: size, mode: mode, allowsUpscaling: allowsUpscaling)
    }
}

// MARK: - Downsampling

extension HResizeProcessor {
    /// The target size to decode at, so the resize starts from an image close to its output.
    var decodingTarget: HImageTargetSize {
        HImageTargetSize(pixelWidth: Int(size.width), pixelHeight: Int(size.height), contentMode: mode == .fit ? .fit : .fill)
    }
}

// MARK: - HImageProcessor

public extension HResizeProcessor {
    /// Identifies the size, mode and upscaling.
    var identifier: String {
        "resize(\(Int(size.width))x\(Int(size.height)),\(mode.rawValue),\(allowsUpscaling))"
    }

    /// Resizes the image.
    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        let source = CGSize(width: image.width, height: image.height)
        let widthRatio = size.width / source.width
        let heightRatio = size.height / source.height

        var drawSize: CGSize
        var canvasSize: CGSize
        switch mode {
        case .fit:
            var ratio = min(widthRatio, heightRatio)
            if !allowsUpscaling { ratio = min(ratio, 1) }
            drawSize = CGSize(width: source.width * ratio, height: source.height * ratio)
            canvasSize = drawSize
        case .fill:
            var ratio = max(widthRatio, heightRatio)
            if !allowsUpscaling { ratio = min(ratio, 1) }
            drawSize = CGSize(width: source.width * ratio, height: source.height * ratio)
            canvasSize = CGSize(width: min(size.width, drawSize.width), height: min(size.height, drawSize.height))
        case .stretch:
            drawSize = allowsUpscaling ? size : CGSize(width: min(size.width, source.width), height: min(size.height, source.height))
            canvasSize = drawSize
        }

        let width = HImageCanvas.pixels(canvasSize.width)
        let height = HImageCanvas.pixels(canvasSize.height)
        if width == image.width, height == image.height, mode != .stretch || drawSize == source {
            return image
        }
        return try HImageCanvas.draw(width: width, height: height) { canvas in
            let origin = CGPoint(x: (CGFloat(width) - drawSize.width) / 2, y: (CGFloat(height) - drawSize.height) / 2)
            canvas.draw(image, in: CGRect(origin: origin, size: drawSize))
        }
    }
}
