//
//  HImageMaskShape.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// The shape of a mask (`.mask(_:)`), outside of which the image becomes transparent, or the
/// outline of a border (`.border(width:color:shape:)`).
public struct HImageMaskShape: Sendable {
    /// The kinds of shape.
    enum Kind: @unchecked Sendable {
        /// See `HImageMaskShape.circle`.
        case circle
        /// See `HImageMaskShape.ellipse`.
        case ellipse
        /// See `HImageMaskShape.roundedRect(radius:)`.
        case roundedRect(CGFloat)
        /// See `HImageMaskShape.capsule`.
        case capsule
        /// See `HImageMaskShape.path(_:id:)`. The path is an immutable copy, safe to read from
        /// any thread, which the SDK does not express as `Sendable`.
        case path(CGPath, id: String)
        /// See `HImageMaskShape.image(_:id:)`.
        case image(CGImage, id: String)
    }

    /// The shape.
    let kind: Kind
}

// MARK: - Shapes

public extension HImageMaskShape {
    /// A circle. As a mask, the image is cropped to its centered square first; as a border, it
    /// follows the ellipse inscribed in the image (put `.mask(.circle)` before the border).
    static let circle = HImageMaskShape(kind: .circle)

    /// The ellipse inscribed in the image.
    static let ellipse = HImageMaskShape(kind: .ellipse)

    /// A rectangle whose shorter sides are fully rounded.
    static let capsule = HImageMaskShape(kind: .capsule)

    /// A rectangle with rounded corners.
    /// - Parameter radius: The corner radius in pixels.
    static func roundedRect(radius: CGFloat) -> HImageMaskShape {
        HImageMaskShape(kind: .roundedRect(radius.isFinite ? max(0, radius) : 0))
    }

    /// A custom path in unit coordinates (`0...1` on both axes, origin at the top left), scaled
    /// to the image.
    /// - Parameters:
    ///   - path: The path.
    ///   - id: Names the path in the cache key: give each different path its own.
    static func path(_ path: CGPath, id: String) -> HImageMaskShape {
        HImageMaskShape(kind: .path(path.copy() ?? path, id: id))
    }

    /// The alpha channel of another image, stretched to the image.
    /// - Parameters:
    ///   - image: The mask image.
    ///   - id: Names the mask in the cache key: give each different mask image its own.
    static func image(_ image: CGImage, id: String) -> HImageMaskShape {
        HImageMaskShape(kind: .image(image, id: id))
    }
}

// MARK: - Geometry

extension HImageMaskShape {
    /// The identifier of the shape in processor identifiers.
    var identifier: String {
        switch kind {
        case .circle: return "circle"
        case .ellipse: return "ellipse"
        case .roundedRect(let radius): return "roundedRect(\(radius))"
        case .capsule: return "capsule"
        case .path(_, let id): return "path(\(id))"
        case .image(_, let id): return "image(\(id))"
        }
    }

    /// The mask image, for `.image` shapes.
    var maskImage: CGImage? {
        if case .image(let image, _) = kind { return image }
        return nil
    }

    /// Whether the shape is `.circle`.
    var isCircle: Bool {
        if case .circle = kind { return true }
        return false
    }

    /// The outline of the shape in a rectangle of the given size, in Core Graphics coordinates
    /// (origin at the bottom left). `nil` for `.image`, which is not a path.
    /// - Parameters:
    ///   - size: The size of the image.
    ///   - inset: How far the outline is moved inwards (half a border width).
    func path(in size: CGSize, inset: CGFloat = 0) -> CGPath? {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return nil }
        switch kind {
        case .circle, .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        case .roundedRect(let radius):
            let corner = min(max(0, radius - inset), rect.width / 2, rect.height / 2)
            return CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        case .capsule:
            let corner = min(rect.width, rect.height) / 2
            return CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        case .path(let path, _):
            // Unit square, origin at the top left → the image, origin at the bottom left.
            var transform = CGAffineTransform(a: rect.width, b: 0, c: 0, d: -rect.height, tx: rect.minX, ty: rect.maxY)
            return path.copy(using: &transform)
        case .image:
            return nil
        }
    }
}
