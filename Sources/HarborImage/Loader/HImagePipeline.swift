//
//  HImagePipeline.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation
import HarborCore
import ImageIO

/// Turns image bytes into an `HImageResult`: format detection, decoding (with downsampling),
/// the processors and the encoding. Runs off `@HRequestManagerActor`.
enum HImagePipeline {
    /// The outcome of rendering bytes.
    struct Rendered: Sendable {
        /// The result handed to the caller.
        let result: HImageResult
        /// The bytes of the processed variant to store on disk, or `nil` when the cache keeps
        /// the original bytes instead: no processor nor encoding, or an animated image or an SVG,
        /// which a still variant would lose (the animation, or the vector resolution).
        let variantData: Data?
    }

    /// What the pipeline needs from the global configuration.
    struct Settings: Sendable {
        /// Decoders registered by the app.
        let decoders: [any HImageDecoder]
        /// The largest image accepted, in pixels.
        let maxImagePixels: Int
    }
}

// MARK: - Rendering

extension HImagePipeline {
    /// Decodes, processes and encodes original bytes.
    /// - Parameters:
    ///   - data: The original bytes.
    ///   - source: Where the bytes came from.
    ///   - resolved: The request.
    ///   - settings: Decoders and limits.
    nonisolated static func render(_ data: Data, source: HImageSource, resolved: HImageResolvedRequest, settings: Settings) async throws(HImageError) -> Rendered {
        let format = try detectFormat(data, decoders: settings.decoders)
        let decoded = try decode(data, format: format, target: resolved.decodingTarget, settings: settings)
        try checkCancellation()

        let context = resolved.processingContext(format: format)
        var image = decoded.image
        for processor in resolved.processors {
            image = try await run(processor, on: image, context: context)
            try checkCancellation()
        }

        var animation: HImageAnimation?
        if let imageSource = decoded.raster?.source {
            animation = HImageAnimation(source: imageSource, maxPixelSize: decoded.raster?.maxPixelSize, processors: resolved.processors, context: context, firstFrame: image)
        }
        let keepsOriginal = animation != nil || format == .svg

        if let encoding = resolved.encoding {
            let encoded = try HImageEncoder.encode(image, as: encoding)
            let result = HImageResult(image: image, data: encoded, format: encoding.imageFormat, source: source, animation: animation)
            return Rendered(result: result, variantData: keepsOriginal ? nil : encoded)
        }
        guard !resolved.processors.isEmpty, !keepsOriginal else {
            return Rendered(result: HImageResult(image: image, data: data, format: format, source: source, animation: animation), variantData: nil)
        }
        // A lossless variant with alpha, so masks keep their transparency.
        let png = try HImageEncoder.encode(image, as: .png)
        return Rendered(result: HImageResult(image: image, data: png, format: .png, source: source), variantData: png)
    }

    /// Decodes a processed variant read from disk, without running the processors again.
    /// - Parameters:
    ///   - data: The variant bytes.
    ///   - settings: Decoders and limits.
    nonisolated static func decodeVariant(_ data: Data, settings: Settings) throws(HImageError) -> HImageResult {
        let format = try detectFormat(data, decoders: settings.decoders)
        let decoded = try decode(data, format: format, target: nil, settings: settings)
        return HImageResult(image: decoded.image, data: data, format: format, source: .disk)
    }

    /// Checks that the bytes are an image, without decoding them.
    /// - Parameters:
    ///   - data: The bytes.
    ///   - decoders: Decoders registered by the app.
    nonisolated static func detectFormat(_ data: Data, decoders: [any HImageDecoder]) throws(HImageError) -> HImageFormat {
        if let decoder = decoders.first(where: { $0.canDecode(data) }) {
            return decoder.format
        }
        guard let format = HImageFormat.detect(data) else { throw .notAnImage }
        return format
    }

    /// Runs processors on an image the app already has (`HarborImage.process(_:with:)`).
    /// - Parameters:
    ///   - image: The image.
    ///   - processors: The processors.
    nonisolated static func process(_ image: CGImage, with processors: [any HImageProcessor]) async throws(HImageError) -> CGImage {
        var output = image
        let context = HImageProcessingContext(format: .png)
        for processor in processors {
            output = try await run(processor, on: output, context: context)
        }
        return output
    }
}

// MARK: - Decoding

extension HImagePipeline {
    /// A decoded first frame and, for raster formats, the ImageIO source behind it.
    private struct Decoded {
        /// The first frame.
        let image: CGImage
        /// The ImageIO decoding, when the image is an animation (GIF, APNG or WebP with several frames).
        let raster: HImageIODecoder.Decoded?
    }

    /// Decodes the bytes with the decoder of their format.
    /// - Parameters:
    ///   - data: The bytes.
    ///   - format: Their format.
    ///   - target: The size to decode at.
    ///   - settings: Decoders and limits.
    nonisolated private static func decode(_ data: Data, format: HImageFormat, target: HImageTargetSize?, settings: Settings) throws(HImageError) -> Decoded {
        if let decoder = settings.decoders.first(where: { $0.format == format && $0.canDecode(data) }) {
            do {
                let image = try decoder.decode(data, targetSize: target)
                guard image.width * image.height <= settings.maxImagePixels else {
                    throw HImageError.tooManyPixels(maxPixels: settings.maxImagePixels)
                }
                return Decoded(image: image, raster: nil)
            } catch let error as HImageError {
                throw error
            } catch {
                throw .decodingFailed
            }
        }
        if format == .svg {
            return Decoded(image: try decodeSVG(data, target: target, maxPixels: settings.maxImagePixels), raster: nil)
        }
        let isAnimatable = format == .gif || format == .png || format == .webp
        let decoded = try HImageIODecoder.decode(data, targetSize: target, maxPixels: settings.maxImagePixels, isAnimatable: isAnimatable)
        return Decoded(image: decoded.image, raster: decoded.isAnimated ? decoded : nil)
    }

    /// Rasterizes an SVG at the target size, or at its intrinsic size (1 pixel per point).
    /// - Parameters:
    ///   - data: The SVG bytes.
    ///   - target: The size to render at.
    ///   - maxPixels: The largest raster accepted.
    nonisolated private static func decodeSVG(_ data: Data, target: HImageTargetSize?, maxPixels: Int) throws(HImageError) -> CGImage {
        do throws(HSVGError) {
            let document = try HSVGDocument(data: data)
            var size = document.intrinsicSize
            if let target, size.width > 0, size.height > 0 {
                // A vector image is rendered at the target size, enlarged if needed.
                let widthRatio = CGFloat(target.pixelWidth) / size.width
                let heightRatio = CGFloat(target.pixelHeight) / size.height
                let factor = target.contentMode == .fit ? min(widthRatio, heightRatio) : max(widthRatio, heightRatio)
                size = CGSize(width: size.width * factor, height: size.height * factor)
            }
            let pixels = CGSize(width: max(1, size.width.rounded()), height: max(1, size.height.rounded()))
            guard pixels.width * pixels.height <= CGFloat(maxPixels) else {
                throw HSVGError.tooLarge
            }
            return try document.render(pixelSize: pixels)
        } catch {
            switch error {
            case .malformed:
                throw .decodingFailed
            case .unsupported(let feature):
                throw .unsupportedFormat("SVG feature \(feature)")
            case .unsafe(let feature):
                throw .unsupportedFormat("SVG with unsafe content (\(feature))")
            case .tooLarge:
                throw .tooManyPixels(maxPixels: maxPixels)
            }
        }
    }
}

// MARK: - Processing

extension HImagePipeline {
    /// Runs one processor, mapping its errors.
    /// - Parameters:
    ///   - processor: The processor.
    ///   - image: The input image.
    ///   - context: The processing context.
    nonisolated private static func run(_ processor: any HImageProcessor, on image: CGImage, context: HImageProcessingContext) async throws(HImageError) -> CGImage {
        do {
            return try await processor.process(image, context: context)
        } catch let error as HImageError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .processingFailed("\(processor.identifier): \(HRequestError.safeDescription(of: error))")
        }
    }

    /// Throws `.cancelled` when the calling task was cancelled.
    nonisolated private static func checkCancellation() throws(HImageError) {
        if Task.isCancelled { throw .cancelled }
    }
}
