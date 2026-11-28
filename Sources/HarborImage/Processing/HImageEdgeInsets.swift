//
//  HImageEdgeInsets.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// Distances from each edge of an image, in pixels.
public struct HImageEdgeInsets: Sendable, Hashable {
    /// Distance from the top edge.
    public let top: CGFloat
    /// Distance from the left edge.
    public let leading: CGFloat
    /// Distance from the bottom edge.
    public let bottom: CGFloat
    /// Distance from the right edge.
    public let trailing: CGFloat

    /// Creates insets. Negative or non-finite values are treated as 0.
    /// - Parameters:
    ///   - top: Distance from the top edge.
    ///   - leading: Distance from the left edge.
    ///   - bottom: Distance from the bottom edge.
    ///   - trailing: Distance from the right edge.
    public init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = Self.sanitized(top)
        self.leading = Self.sanitized(leading)
        self.bottom = Self.sanitized(bottom)
        self.trailing = Self.sanitized(trailing)
    }

    /// Creates the same inset on every edge.
    /// - Parameter all: The distance from every edge.
    public init(all: CGFloat) {
        self.init(top: all, leading: all, bottom: all, trailing: all)
    }
}

// MARK: - Identifier

extension HImageEdgeInsets {
    /// The identifier of the insets in processor identifiers.
    var identifier: String {
        "\(top),\(leading),\(bottom),\(trailing)"
    }

    /// Turns a negative or non-finite inset into 0.
    /// - Parameter value: The inset.
    private static func sanitized(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : 0
    }
}
