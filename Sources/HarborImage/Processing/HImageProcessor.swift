//
//  HImageProcessor.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// A step that turns a decoded image into another one (resize, crop, mask, filter, ...). The
/// built-in processors are available as static members (`.resize(to:mode:allowsUpscaling:)`,
/// `.mask(.circle)`, `.blur(radius:)`, ...); conform your own type to add one:
///
/// ```swift
/// struct SepiaProcessor: HImageProcessor {
///     let intensity: Double
///     var identifier: String { "sepia(\(intensity))" }
///     func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
///         ...
///     }
/// }
///
/// HImageRequest(url: url, processors: [.resize(to: size, mode: .fill), SepiaProcessor(intensity: 0.8)])
/// ```
///
/// Processors run off the main actor, in the order given. A processor that throws fails the
/// load (or `HarborImage.process(_:with:)`) with the `HImageError` it threw, `.cancelled` for a
/// `CancellationError`, or `.processingFailed` otherwise.
public protocol HImageProcessor: Sendable {
    /// Identifies the processor and its configuration. It is part of the cache key, so it must
    /// be stable across launches and different for every configuration that changes the output
    /// (include every parameter). An identifier that changes (for example one that contains a
    /// memory address) means the processed image is never found in the cache.
    var identifier: String { get }

    /// Processes the image.
    /// - Parameters:
    ///   - image: The input image.
    ///   - context: What is known about the image.
    /// - Returns: The processed image.
    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage
}
