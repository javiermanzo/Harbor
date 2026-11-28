//
//  HImageProcessingContext.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// What a processor knows about the image it processes.
public struct HImageProcessingContext: Sendable {
    /// The format of the original image; `.png` in `HarborImage.process(_:with:)`.
    public let format: HImageFormat
    /// The size the request decodes at: its `targetSize`, or a first `.resize(to:)`; `nil` at
    /// full size (always in `HarborImage.process(_:with:)`).
    public let targetSize: HImageTargetSize?

    /// Creates a context.
    /// - Parameters:
    ///   - format: The format of the original image.
    ///   - targetSize: The size the image was decoded at.
    public init(format: HImageFormat, targetSize: HImageTargetSize? = nil) {
        self.format = format
        self.targetSize = targetSize
    }
}
