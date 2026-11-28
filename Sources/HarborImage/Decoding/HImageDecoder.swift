//
//  HImageDecoder.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// A decoder for a format HarborImage does not decode itself (AVIF on older systems, JPEG XL, a
/// fuller SVG renderer, ...). Register it with `HarborImage.registerDecoder(_:)`; registered
/// decoders are asked before the built-in ones, in registration order.
///
/// ```swift
/// struct JXLDecoder: HImageDecoder {
///     let format = HImageFormat(rawValue: "jxl")
///     func canDecode(_ data: Data) -> Bool { data.starts(with: [0xFF, 0x0A]) }
///     func decode(_ data: Data, targetSize: HImageTargetSize?) throws -> CGImage { ... }
/// }
/// ```
public protocol HImageDecoder: Sendable {
    /// The format this decoder reads, reported in `HImageResult.format` when the image is not
    /// processed nor encoded.
    var format: HImageFormat { get }

    /// Whether the bytes are in this decoder's format. Called for every load, so keep it to a
    /// signature check.
    /// - Parameter data: The image bytes.
    func canDecode(_ data: Data) -> Bool

    /// Decodes the bytes, off the main actor. Throwing an `HImageError` reports it as-is; any
    /// other error is reported as `.decodingFailed`. The result is checked against
    /// `HarborImage.setMaxImagePixels(_:)` only after decoding, so check the declared size of
    /// the image before allocating it.
    /// - Parameters:
    ///   - data: The image bytes.
    ///   - targetSize: The size to decode at when downsampling is requested, in pixels.
    /// - Returns: The decoded image.
    func decode(_ data: Data, targetSize: HImageTargetSize?) throws -> CGImage
}
