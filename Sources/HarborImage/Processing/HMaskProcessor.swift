//
//  HMaskProcessor.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// Masks the image with a shape: what falls outside it becomes transparent. Keep the result in
/// a format with alpha (the default PNG for processed images, or `.png` / `.heic` encodings).
public struct HMaskProcessor: HImageProcessor {
    /// The mask shape.
    public let shape: HImageMaskShape

    /// Creates a mask processor.
    /// - Parameter shape: The mask shape.
    public init(shape: HImageMaskShape) {
        self.shape = shape
    }
}

// MARK: - Factory

public extension HImageProcessor where Self == HMaskProcessor {
    /// Masks the image with a shape.
    /// - Parameter shape: The mask shape.
    static func mask(_ shape: HImageMaskShape) -> HMaskProcessor {
        HMaskProcessor(shape: shape)
    }

    /// Rounds the corners of the image, a shortcut for `.mask(.roundedRect(radius:))`.
    /// - Parameter radius: The corner radius in pixels.
    static func roundedCorners(_ radius: CGFloat) -> HMaskProcessor {
        HMaskProcessor(shape: .roundedRect(radius: radius))
    }
}

// MARK: - HImageProcessor

public extension HMaskProcessor {
    /// Identifies the shape.
    var identifier: String {
        "mask(\(shape.identifier))"
    }

    /// Masks the image.
    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        var input = image
        if shape.isCircle, image.width != image.height {
            input = try await HCropProcessor(region: .size(CGSize(width: min(image.width, image.height), height: min(image.width, image.height)), alignment: .center))
                .process(image, context: context)
        }

        let size = CGSize(width: input.width, height: input.height)
        let bounds = CGRect(origin: .zero, size: size)
        return try HImageCanvas.draw(width: input.width, height: input.height) { canvas in
            if let mask = shape.maskImage {
                canvas.draw(input, in: bounds)
                // Keeps the image where the mask is opaque.
                canvas.setBlendMode(.destinationIn)
                canvas.draw(mask, in: bounds)
                return
            }
            guard let path = shape.path(in: size) else { return }
            canvas.addPath(path)
            canvas.clip()
            canvas.draw(input, in: bounds)
        }
    }
}
