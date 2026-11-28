//
//  HBlurProcessor.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import CoreImage
import Foundation

/// Applies a Gaussian blur. The edges are extended before blurring, so they do not fade to transparent.
public struct HBlurProcessor: HImageProcessor {
    /// The blur radius in pixels; negative or non-finite values become 0, which returns the
    /// image unchanged.
    public let radius: Double

    /// Creates a blur processor.
    /// - Parameter radius: The blur radius in pixels.
    public init(radius: Double) {
        self.radius = radius.isFinite ? max(0, radius) : 0
    }
}

// MARK: - Factory

public extension HImageProcessor where Self == HBlurProcessor {
    /// Applies a Gaussian blur.
    /// - Parameter radius: The blur radius in pixels.
    static func blur(radius: Double) -> HBlurProcessor {
        HBlurProcessor(radius: radius)
    }
}

// MARK: - HImageProcessor

public extension HBlurProcessor {
    /// Identifies the radius.
    var identifier: String {
        "blur(\(radius))"
    }

    /// Blurs the image.
    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        guard radius > 0 else { return image }
        return try HImageCoreImage.apply(to: image) { input in
            input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
        }
    }
}
