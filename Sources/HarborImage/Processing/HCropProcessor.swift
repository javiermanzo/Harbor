//
//  HCropProcessor.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// Crops the image to a rectangle, or to a size placed with an alignment. Coordinates are in
/// pixels with the origin at the top left; the crop is limited to the image bounds.
public struct HCropProcessor: HImageProcessor {
    /// What is cropped.
    public enum Region: Sendable, Hashable {
        /// A rectangle in pixels, origin at the top left.
        case rect(CGRect)
        /// A size in pixels, placed with an alignment.
        case size(CGSize, alignment: HImageAlignment)
    }

    /// The cropped region.
    public let region: Region

    /// Creates a crop processor.
    /// - Parameter region: The cropped region.
    public init(region: Region) {
        self.region = region
    }
}

// MARK: - Factory

public extension HImageProcessor where Self == HCropProcessor {
    /// Crops the image to a rectangle in pixels, origin at the top left.
    /// - Parameter rect: The rectangle.
    static func crop(rect: CGRect) -> HCropProcessor {
        HCropProcessor(region: .rect(rect))
    }

    /// Crops the image to a size in pixels, placed with an alignment.
    /// - Parameters:
    ///   - size: The size.
    ///   - alignment: Where the crop is placed. Default: `.center`.
    static func crop(size: CGSize, alignment: HImageAlignment = .center) -> HCropProcessor {
        HCropProcessor(region: .size(size, alignment: alignment))
    }
}

// MARK: - HImageProcessor

public extension HCropProcessor {
    /// Identifies the cropped region.
    var identifier: String {
        switch region {
        case .rect(let rect):
            return "crop(\(rect.minX),\(rect.minY),\(rect.width),\(rect.height))"
        case .size(let size, let alignment):
            return "crop(\(size.width)x\(size.height),\(alignment.rawValue))"
        }
    }

    /// Crops the image.
    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect: CGRect
        switch region {
        case .rect(let requested):
            rect = requested
        case .size(let size, let alignment):
            let clamped = CGSize(width: min(size.width, bounds.width), height: min(size.height, bounds.height))
            rect = CGRect(origin: alignment.origin(of: clamped, in: bounds.size), size: clamped)
        }
        let cropRect = rect.integral.intersection(bounds)
        guard !cropRect.isNull, cropRect.width >= 1, cropRect.height >= 1 else {
            throw HImageError.processingFailed("The crop rectangle is outside the image")
        }
        if cropRect == bounds { return image }
        // Redrawn rather than `cropping(to:)`, which keeps the whole source image alive: a small
        // crop of a large photo would hold its full buffer in the memory cache.
        return try HImageCanvas.draw(width: Int(cropRect.width), height: Int(cropRect.height)) { canvas in
            let origin = CGPoint(x: -cropRect.minX, y: cropRect.maxY - bounds.height)
            canvas.draw(image, in: CGRect(origin: origin, size: bounds.size))
        }
    }
}
