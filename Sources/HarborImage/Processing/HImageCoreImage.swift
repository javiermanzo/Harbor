//
//  HImageCoreImage.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import CoreImage
import Foundation

/// Runs Core Image filters for the processors (blur, color adjustments).
enum HImageCoreImage {
    /// The shared context, created without intermediate caching. `CIContext` is thread-safe and
    /// expensive to create, so one is reused.
    private static let context = HCIContextBox(context: CIContext(options: [.cacheIntermediates: false]))

    /// Applies a filter chain to the image and renders it at the image's size.
    /// - Parameters:
    ///   - image: The input image.
    ///   - transform: Builds the output from the input `CIImage`.
    /// - Throws: `.processingFailed` when the output cannot be rendered.
    static func apply(to image: CGImage, _ transform: (CIImage) -> CIImage?) throws -> CGImage {
        let input = CIImage(cgImage: image)
        guard let output = transform(input),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let rendered = context.context.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw HImageError.processingFailed("Core Image could not render the image")
        }
        return rendered
    }
}

// MARK: - Context Box

/// Holds the shared `CIContext`. Apple documents `CIContext` as safe to use from multiple
/// threads, which the SDK does not express as `Sendable`.
private struct HCIContextBox: @unchecked Sendable {
    /// The context.
    let context: CIContext
}
