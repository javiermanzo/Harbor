//
//  HColorAdjustProcessor.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import CoreImage
import Foundation

/// Adjusts brightness, contrast and saturation (Core Image's color controls). `.grayscale` is
/// this processor with zero saturation.
public struct HColorAdjustProcessor: HImageProcessor {
    /// Added to every channel, in `-1...1`; 0 leaves the image unchanged.
    public let brightness: Double
    /// Contrast multiplier; 1 leaves the image unchanged, negative values become 0.
    public let contrast: Double
    /// Saturation multiplier; 0 is grayscale, 1 leaves the image unchanged, negative values become 0.
    public let saturation: Double

    /// Creates a color adjustment.
    /// - Parameters:
    ///   - brightness: Added to every channel, in `-1...1`. Default: 0.
    ///   - contrast: Contrast multiplier. Default: 1.
    ///   - saturation: Saturation multiplier. Default: 1.
    public init(brightness: Double = 0, contrast: Double = 1, saturation: Double = 1) {
        self.brightness = brightness.isFinite ? min(max(brightness, -1), 1) : 0
        self.contrast = contrast.isFinite ? max(0, contrast) : 1
        self.saturation = saturation.isFinite ? max(0, saturation) : 1
    }
}

// MARK: - Factory

public extension HImageProcessor where Self == HColorAdjustProcessor {
    /// Adjusts brightness, contrast and saturation.
    /// - Parameters:
    ///   - brightness: Added to every channel, in `-1...1`. Default: 0.
    ///   - contrast: Contrast multiplier. Default: 1.
    ///   - saturation: Saturation multiplier. Default: 1.
    static func adjust(brightness: Double = 0, contrast: Double = 1, saturation: Double = 1) -> HColorAdjustProcessor {
        HColorAdjustProcessor(brightness: brightness, contrast: contrast, saturation: saturation)
    }

    /// Removes the color.
    static var grayscale: HColorAdjustProcessor {
        HColorAdjustProcessor(saturation: 0)
    }
}

// MARK: - HImageProcessor

public extension HColorAdjustProcessor {
    /// Identifies the adjustments.
    var identifier: String {
        "adjust(\(brightness),\(contrast),\(saturation))"
    }

    /// Adjusts the colors.
    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        guard brightness != 0 || contrast != 1 || saturation != 1 else { return image }
        return try HImageCoreImage.apply(to: image) { input in
            input.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: brightness,
                kCIInputContrastKey: contrast,
                kCIInputSaturationKey: saturation,
            ])
        }
    }
}
