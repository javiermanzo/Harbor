//
//  HImageIODecoder.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation
import ImageIO

/// Decodes the raster formats ImageIO supports (JPEG, PNG, GIF, WebP, HEIC, AVIF, TIFF, BMP,
/// ICO), applying the EXIF orientation and downsampling while decoding, so a large image is
/// never fully decoded only to be scaled down.
enum HImageIODecoder {
    /// A decoded raster image.
    struct Decoded: @unchecked Sendable {
        /// The first frame, oriented and downsampled.
        let image: CGImage
        /// The image source, kept for animated images to decode their other frames. ImageIO
        /// sources are only read through `HImageAnimation`, which serializes access.
        let source: CGImageSource
        /// The size frames were decoded at, or `nil` for the full size.
        let maxPixelSize: Int?
        /// Whether the image is an animation (an animatable format with several frames).
        let isAnimated: Bool
    }

    /// Decodes the bytes: the first frame of an animatable format, or the largest image of a
    /// file that holds several (an ICO with several sizes, a multi-page TIFF).
    /// - Parameters:
    ///   - data: The image bytes.
    ///   - targetSize: The size to downsample to, or `nil` for the full size. It is compared
    ///     with the size the image is displayed at, after the EXIF orientation.
    ///   - maxPixels: The largest pixel count accepted before decoding.
    ///   - isAnimatable: Whether several frames are an animation (GIF, APNG, WebP).
    /// - Throws: `.tooManyPixels` past `maxPixels`, `.decodingFailed` for corrupted bytes.
    static func decode(_ data: Data, targetSize: HImageTargetSize?, maxPixels: Int, isAnimatable: Bool) throws(HImageError) -> Decoded {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            throw .decodingFailed
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw .decodingFailed }
        let index = isAnimatable ? 0 : largestImageIndex(source: source, count: count)

        guard let size = pixelSize(source: source, index: index) else { throw .decodingFailed }
        guard size.width * size.height <= CGFloat(maxPixels) else {
            throw .tooManyPixels(maxPixels: maxPixels)
        }

        var maxPixelSize: Int?
        if let targetSize {
            let factor = targetSize.scaleFactor(for: displayedSize(source: source, index: index, pixelSize: size))
            if factor < 1 {
                maxPixelSize = max(1, Int((max(size.width, size.height) * factor).rounded(.up)))
            }
        }

        guard let image = decodeFrame(source: source, index: index, maxPixelSize: maxPixelSize) else {
            throw .decodingFailed
        }
        return Decoded(image: image, source: source, maxPixelSize: maxPixelSize, isAnimated: isAnimatable && count > 1)
    }

    /// The index of the largest image of a file, for formats where several images are sizes
    /// or pages rather than frames. Only the first 64 are compared.
    /// - Parameters:
    ///   - source: The image source.
    ///   - count: The number of images.
    private static func largestImageIndex(source: CGImageSource, count: Int) -> Int {
        guard count > 1 else { return 0 }
        var best = (index: 0, area: CGFloat(0))
        for index in 0..<min(count, 64) {
            guard let size = pixelSize(source: source, index: index) else { continue }
            if size.width * size.height > best.area {
                best = (index, size.width * size.height)
            }
        }
        return best.index
    }

    /// The size an image is displayed at: its pixel size, with width and height swapped for the
    /// EXIF orientations that rotate it by 90° (5 to 8).
    /// - Parameters:
    ///   - source: The image source.
    ///   - index: The image index.
    ///   - pixelSize: The stored pixel size.
    private static func displayedSize(source: CGImageSource, index: Int, pixelSize: CGSize) -> CGSize {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? CGSize(width: pixelSize.height, height: pixelSize.width) : pixelSize
    }

    /// Decodes one frame, oriented, at most `maxPixelSize` on its longest side.
    /// - Parameters:
    ///   - source: The image source.
    ///   - index: The frame index.
    ///   - maxPixelSize: The longest side in pixels, or `nil` for the full size.
    static func decodeFrame(source: CGImageSource, index: Int, maxPixelSize: Int?) -> CGImage? {
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxPixelSize {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        } else if let size = pixelSize(source: source, index: index) {
            // The thumbnail API applies the EXIF orientation; at the full size it decodes the whole image.
            options[kCGImageSourceThumbnailMaxPixelSize] = Int(max(size.width, size.height))
        }
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    /// The pixel size of a frame, before orientation.
    /// - Parameters:
    ///   - source: The image source.
    ///   - index: The frame index. Default: 0.
    static func pixelSize(source: CGImageSource, index: Int = 0) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }
}
