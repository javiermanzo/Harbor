//
//  HFlipProcessor.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// Mirrors the image horizontally or vertically.
public struct HFlipProcessor: HImageProcessor {
    /// The mirroring axis.
    public enum Direction: String, Sendable, Hashable {
        /// Left and right are swapped.
        case horizontal
        /// Top and bottom are swapped.
        case vertical
    }

    /// The mirroring axis.
    public let direction: Direction

    /// Creates a flip processor.
    /// - Parameter direction: The mirroring axis.
    public init(direction: Direction) {
        self.direction = direction
    }
}

// MARK: - Factory

public extension HImageProcessor where Self == HFlipProcessor {
    /// Mirrors the image.
    /// - Parameter direction: The mirroring axis.
    static func flip(_ direction: HFlipProcessor.Direction) -> HFlipProcessor {
        HFlipProcessor(direction: direction)
    }
}

// MARK: - HImageProcessor

public extension HFlipProcessor {
    /// Identifies the axis.
    var identifier: String {
        "flip(\(direction.rawValue))"
    }

    /// Mirrors the image.
    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        return try HImageCanvas.draw(width: image.width, height: image.height) { canvas in
            switch direction {
            case .horizontal:
                canvas.translateBy(x: width, y: 0)
                canvas.scaleBy(x: -1, y: 1)
            case .vertical:
                canvas.translateBy(x: 0, y: height)
                canvas.scaleBy(x: 1, y: -1)
            }
            canvas.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
