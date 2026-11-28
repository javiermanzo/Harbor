//
//  HPaddingProcessor.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// Adds space around the image, transparent or filled with a color.
public struct HPaddingProcessor: HImageProcessor {
    /// The space added on each edge, in pixels.
    public let insets: HImageEdgeInsets
    /// The color of the added space.
    public let color: HImageColor

    /// Creates a padding processor.
    /// - Parameters:
    ///   - insets: The space added on each edge, in pixels.
    ///   - color: The color of the added space. Default: `.clear`.
    public init(insets: HImageEdgeInsets, color: HImageColor = .clear) {
        self.insets = insets
        self.color = color
    }
}

// MARK: - Factory

public extension HImageProcessor where Self == HPaddingProcessor {
    /// Adds space around the image.
    /// - Parameters:
    ///   - insets: The space added on each edge, in pixels.
    ///   - color: The color of the added space. Default: `.clear`.
    static func padding(_ insets: HImageEdgeInsets, color: HImageColor = .clear) -> HPaddingProcessor {
        HPaddingProcessor(insets: insets, color: color)
    }
}

// MARK: - HImageProcessor

public extension HPaddingProcessor {
    /// Identifies the insets and color.
    var identifier: String {
        "padding(\(insets.identifier),\(color.identifier))"
    }

    /// Adds the padding.
    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        let width = image.width + Int((insets.leading + insets.trailing).rounded())
        let height = image.height + Int((insets.top + insets.bottom).rounded())
        guard width != image.width || height != image.height else { return image }
        return try HImageCanvas.draw(width: width, height: height) { canvas in
            if color.alpha > 0 {
                canvas.setFillColor(color.cgColor)
                canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            let rect = CGRect(x: insets.leading.rounded(), y: insets.top.rounded(), width: CGFloat(image.width), height: CGFloat(image.height))
            canvas.draw(image, in: HImageCanvas.flipped(rect, height: CGFloat(height)))
        }
    }
}
