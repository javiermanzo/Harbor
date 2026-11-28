//
//  HBorderProcessor.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// Draws a border inside the edges of the image, following a shape. Combine it with a mask of
/// the same shape: `[.mask(.circle), .border(width: 4, color: .white, shape: .circle)]`.
public struct HBorderProcessor: HImageProcessor {
    /// The border width in pixels.
    public let width: CGFloat
    /// The border color.
    public let color: HImageColor
    /// The shape the border follows; `.image` masks draw a rectangular border.
    public let shape: HImageMaskShape

    /// Creates a border processor.
    /// - Parameters:
    ///   - width: The border width in pixels.
    ///   - color: The border color.
    ///   - shape: The shape the border follows. Default: `.roundedRect(radius: 0)`, the image edges.
    public init(width: CGFloat, color: HImageColor, shape: HImageMaskShape = .roundedRect(radius: 0)) {
        self.width = width.isFinite ? max(0, width) : 0
        self.color = color
        self.shape = shape
    }
}

// MARK: - Factory

public extension HImageProcessor where Self == HBorderProcessor {
    /// Draws a border inside the edges of the image.
    /// - Parameters:
    ///   - width: The border width in pixels.
    ///   - color: The border color.
    ///   - shape: The shape the border follows. Default: the image edges.
    static func border(width: CGFloat, color: HImageColor, shape: HImageMaskShape = .roundedRect(radius: 0)) -> HBorderProcessor {
        HBorderProcessor(width: width, color: color, shape: shape)
    }
}

// MARK: - HImageProcessor

public extension HBorderProcessor {
    /// Identifies the width, color and shape.
    var identifier: String {
        "border(\(width),\(color.identifier),\(shape.identifier))"
    }

    /// Draws the border.
    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        guard width > 0 else { return image }
        let size = CGSize(width: image.width, height: image.height)
        return try HImageCanvas.draw(width: image.width, height: image.height) { canvas in
            canvas.draw(image, in: CGRect(origin: .zero, size: size))
            let outline = shape.maskImage == nil ? shape : .roundedRect(radius: 0)
            guard let path = outline.path(in: size, inset: width / 2) else { return }
            canvas.addPath(path)
            canvas.setStrokeColor(color.cgColor)
            canvas.setLineWidth(width)
            canvas.strokePath()
        }
    }
}
