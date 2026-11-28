//
//  HImageAlignment.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// Where a crop or an overlay is placed inside an image. `leading` is always the left edge.
public enum HImageAlignment: String, Sendable, Hashable {
    /// Top left corner.
    case topLeading
    /// Top edge, centered horizontally.
    case top
    /// Top right corner.
    case topTrailing
    /// Left edge, centered vertically.
    case leading
    /// The center.
    case center
    /// Right edge, centered vertically.
    case trailing
    /// Bottom left corner.
    case bottomLeading
    /// Bottom edge, centered horizontally.
    case bottom
    /// Bottom right corner.
    case bottomTrailing
}

// MARK: - Placement

extension HImageAlignment {
    /// The origin of a rectangle of `size` aligned inside `container`, in top-left coordinates.
    /// - Parameters:
    ///   - size: The size of the placed rectangle.
    ///   - container: The size of the container.
    ///   - margin: The distance kept from the container's edges.
    func origin(of size: CGSize, in container: CGSize, margin: CGFloat = 0) -> CGPoint {
        let minX = margin
        let midX = (container.width - size.width) / 2
        let maxX = container.width - size.width - margin
        let minY = margin
        let midY = (container.height - size.height) / 2
        let maxY = container.height - size.height - margin
        switch self {
        case .topLeading: return CGPoint(x: minX, y: minY)
        case .top: return CGPoint(x: midX, y: minY)
        case .topTrailing: return CGPoint(x: maxX, y: minY)
        case .leading: return CGPoint(x: minX, y: midY)
        case .center: return CGPoint(x: midX, y: midY)
        case .trailing: return CGPoint(x: maxX, y: midY)
        case .bottomLeading: return CGPoint(x: minX, y: maxY)
        case .bottom: return CGPoint(x: midX, y: maxY)
        case .bottomTrailing: return CGPoint(x: maxX, y: maxY)
        }
    }
}
