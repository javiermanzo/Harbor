//
//  InvertProcessor.swift
//  HarborExample
//
//  A custom HImageProcessor
//

import CoreImage
import HarborImage

/// A custom `HImageProcessor`: inverts the colors with Core Image. The identifier is part of the
/// cache key, so it is stable and includes every parameter (there are none here).
struct InvertProcessor: HImageProcessor {
    var identifier: String { "invert" }

    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        let input = CIImage(cgImage: image)
        guard let output = CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: input])?.outputImage,
              let result = CIContext().createCGImage(output, from: input.extent) else {
            throw HImageError.processingFailed("invert: Core Image failed")
        }
        return result
    }
}
