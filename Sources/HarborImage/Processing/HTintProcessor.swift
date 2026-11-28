//
//  HTintProcessor.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// Paints the opaque parts of the image with a color, keeping its alpha: turns an icon into a
/// template of that color. A translucent color blends with the image instead.
public struct HTintProcessor: HImageProcessor {
    /// The tint color.
    public let color: HImageColor

    /// Creates a tint processor.
    /// - Parameter color: The tint color.
    public init(color: HImageColor) {
        self.color = color
    }
}

// MARK: - Factory

public extension HImageProcessor where Self == HTintProcessor {
    /// Paints the opaque parts of the image with a color.
    /// - Parameter color: The tint color.
    static func tint(_ color: HImageColor) -> HTintProcessor {
        HTintProcessor(color: color)
    }
}

// MARK: - HImageProcessor

public extension HTintProcessor {
    /// Identifies the color.
    var identifier: String {
        "tint(\(color.identifier))"
    }

    /// Tints the image.
    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        return try HImageCanvas.draw(width: image.width, height: image.height) { canvas in
            canvas.draw(image, in: bounds)
            canvas.setBlendMode(.sourceAtop)
            canvas.setFillColor(color.cgColor)
            canvas.fill(bounds)
        }
    }
}
