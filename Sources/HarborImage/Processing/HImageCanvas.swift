//
//  HImageCanvas.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// Bitmap contexts for the processors: premultiplied RGBA in sRGB, high-quality interpolation.
///
/// Core Graphics puts the origin at the bottom left; the processors describe rectangles and
/// shapes with the origin at the top left, like the image itself, and convert them with
/// `flipped(_:height:)`.
enum HImageCanvas {
    /// The largest side of a canvas, in pixels.
    static let maxSide = 32_768

    /// Draws into a new transparent canvas and returns the image.
    /// - Parameters:
    ///   - width: Width in pixels.
    ///   - height: Height in pixels.
    ///   - body: The drawing, with the origin at the bottom left.
    /// - Throws: `.processingFailed` when the canvas cannot be created.
    static func draw(width: Int, height: Int, _ body: (CGContext) throws -> Void) throws -> CGImage {
        guard width > 0, height > 0, width <= maxSide, height <= maxSide,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw HImageError.processingFailed("Cannot create a \(width)x\(height) canvas")
        }
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        try body(context)
        guard let image = context.makeImage() else {
            throw HImageError.processingFailed("Cannot read the canvas")
        }
        return image
    }

    /// Converts a rectangle from top-left coordinates to Core Graphics coordinates.
    /// - Parameters:
    ///   - rect: The rectangle, origin at the top left.
    ///   - height: The canvas height.
    static func flipped(_ rect: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Rounds a length to a whole number of pixels, at least 1.
    /// - Parameter value: The length.
    static func pixels(_ value: CGFloat) -> Int {
        guard value.isFinite else { return 1 }
        return max(1, Int(value.rounded()))
    }
}
