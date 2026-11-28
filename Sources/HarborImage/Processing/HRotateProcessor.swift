//
//  HRotateProcessor.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// Rotates the image clockwise. The output grows to fit the rotated image; the uncovered
/// corners are transparent. The EXIF orientation is already applied while decoding.
public struct HRotateProcessor: HImageProcessor {
    /// The clockwise rotation in degrees, normalized to `0..<360`; a non-finite value becomes 0.
    public let degrees: Double

    /// Creates a rotate processor.
    /// - Parameter degrees: The clockwise rotation in degrees.
    public init(degrees: Double) {
        let normalized = degrees.isFinite ? degrees.truncatingRemainder(dividingBy: 360) : 0
        self.degrees = normalized < 0 ? normalized + 360 : normalized
    }
}

// MARK: - Factory

public extension HImageProcessor where Self == HRotateProcessor {
    /// Rotates the image clockwise.
    /// - Parameter degrees: The clockwise rotation in degrees.
    static func rotate(degrees: Double) -> HRotateProcessor {
        HRotateProcessor(degrees: degrees)
    }
}

// MARK: - HImageProcessor

public extension HRotateProcessor {
    /// Identifies the rotation.
    var identifier: String {
        "rotate(\(degrees))"
    }

    /// Rotates the image.
    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        guard degrees != 0 else { return image }
        let radians = CGFloat(degrees * .pi / 180)
        let size = CGSize(width: image.width, height: image.height)
        let bounds = CGRect(origin: .zero, size: size).applying(CGAffineTransform(rotationAngle: radians))
        // Right angles produce exact sizes; float noise would add a transparent pixel row.
        let isRightAngle = degrees.truncatingRemainder(dividingBy: 90) == 0
        let width = isRightAngle ? Int(abs(bounds.width).rounded()) : Int(abs(bounds.width).rounded(.up))
        let height = isRightAngle ? Int(abs(bounds.height).rounded()) : Int(abs(bounds.height).rounded(.up))
        return try HImageCanvas.draw(width: width, height: height) { canvas in
            canvas.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
            // Core Graphics rotates counterclockwise with the origin at the bottom left.
            canvas.rotate(by: -radians)
            canvas.draw(image, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}
