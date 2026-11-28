//
//  HSVGPath.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// The geometry of a shape in SVG user units, stored as value-type segments so it is
/// `Sendable` (`CGPath` is not). Arcs are already converted to cubic Bézier curves.
struct HSVGPath: Sendable, Equatable {
    /// One drawing command of the path.
    enum Segment: Sendable, Equatable {
        /// Starts a new subpath at the point.
        case move(CGPoint)
        /// A straight line to the point.
        case line(CGPoint)
        /// A quadratic Bézier curve to `to` with the control point `control`.
        case quad(control: CGPoint, to: CGPoint)
        /// A cubic Bézier curve to `to` with the control points `control1` and `control2`.
        case cubic(control1: CGPoint, control2: CGPoint, to: CGPoint)
        /// Closes the current subpath.
        case close
    }

    /// The segments, in drawing order.
    var segments: [Segment] = []
}

// MARK: - Building

extension HSVGPath {
    /// Whether the path has no segments (a lone moveto is not empty).
    var isEmpty: Bool {
        segments.isEmpty
    }

    /// Appends a `move` segment.
    /// - Parameter point: The start of the new subpath.
    mutating func move(to point: CGPoint) {
        segments.append(.move(point))
    }

    /// Appends a `line` segment.
    /// - Parameter point: The end of the line.
    mutating func line(to point: CGPoint) {
        segments.append(.line(point))
    }

    /// Appends a `cubic` segment.
    /// - Parameters:
    ///   - point: The end of the curve.
    ///   - control1: The first control point.
    ///   - control2: The second control point.
    mutating func cubic(to point: CGPoint, control1: CGPoint, control2: CGPoint) {
        segments.append(.cubic(control1: control1, control2: control2, to: point))
    }

    /// Appends a `close` segment.
    mutating func close() {
        segments.append(.close)
    }

    /// A rectangle with optional elliptical corners, starting at `(x + rx, y)` and running
    /// clockwise in SVG coordinates (towards +x first), as the SVG spec defines for `rect`.
    /// - Parameters:
    ///   - rect: The rectangle.
    ///   - radii: The corner radii, already clamped to half the width and height.
    /// - Returns: The path.
    static func rect(_ rect: CGRect, radii: CGSize) -> HSVGPath {
        var path = HSVGPath()
        let rx = radii.width
        let ry = radii.height
        guard rx > 0, ry > 0 else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.line(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.close()
            return path
        }
        let kx = rx * kappa
        let ky = ry * kappa
        path.move(to: CGPoint(x: rect.minX + rx, y: rect.minY))
        path.line(to: CGPoint(x: rect.maxX - rx, y: rect.minY))
        path.cubic(to: CGPoint(x: rect.maxX, y: rect.minY + ry),
                   control1: CGPoint(x: rect.maxX - rx + kx, y: rect.minY),
                   control2: CGPoint(x: rect.maxX, y: rect.minY + ry - ky))
        path.line(to: CGPoint(x: rect.maxX, y: rect.maxY - ry))
        path.cubic(to: CGPoint(x: rect.maxX - rx, y: rect.maxY),
                   control1: CGPoint(x: rect.maxX, y: rect.maxY - ry + ky),
                   control2: CGPoint(x: rect.maxX - rx + kx, y: rect.maxY))
        path.line(to: CGPoint(x: rect.minX + rx, y: rect.maxY))
        path.cubic(to: CGPoint(x: rect.minX, y: rect.maxY - ry),
                   control1: CGPoint(x: rect.minX + rx - kx, y: rect.maxY),
                   control2: CGPoint(x: rect.minX, y: rect.maxY - ry + ky))
        path.line(to: CGPoint(x: rect.minX, y: rect.minY + ry))
        path.cubic(to: CGPoint(x: rect.minX + rx, y: rect.minY),
                   control1: CGPoint(x: rect.minX, y: rect.minY + ry - ky),
                   control2: CGPoint(x: rect.minX + rx - kx, y: rect.minY))
        path.close()
        return path
    }

    /// An ellipse starting at `(cx + rx, cy)` and running clockwise in SVG coordinates, as
    /// the SVG spec defines for `circle` and `ellipse`.
    /// - Parameters:
    ///   - center: The center.
    ///   - radii: The horizontal and vertical radii.
    /// - Returns: The path.
    static func ellipse(center: CGPoint, radii: CGSize) -> HSVGPath {
        var path = HSVGPath()
        let rx = radii.width
        let ry = radii.height
        let kx = rx * kappa
        let ky = ry * kappa
        let cx = center.x
        let cy = center.y
        path.move(to: CGPoint(x: cx + rx, y: cy))
        path.cubic(to: CGPoint(x: cx, y: cy + ry), control1: CGPoint(x: cx + rx, y: cy + ky), control2: CGPoint(x: cx + kx, y: cy + ry))
        path.cubic(to: CGPoint(x: cx - rx, y: cy), control1: CGPoint(x: cx - kx, y: cy + ry), control2: CGPoint(x: cx - rx, y: cy + ky))
        path.cubic(to: CGPoint(x: cx, y: cy - ry), control1: CGPoint(x: cx - rx, y: cy - ky), control2: CGPoint(x: cx - kx, y: cy - ry))
        path.cubic(to: CGPoint(x: cx + rx, y: cy), control1: CGPoint(x: cx + kx, y: cy - ry), control2: CGPoint(x: cx + rx, y: cy - ky))
        path.close()
        return path
    }

    /// The distance of the control points of a cubic quarter-circle approximation, as a
    /// fraction of the radius: `4/3 * (sqrt(2) - 1)`.
    private static let kappa: CGFloat = 0.552_284_749_830_793_4
}

// MARK: - Core Graphics

extension HSVGPath {
    /// Builds a `CGPath` with the segments, transformed by `transform`.
    /// - Parameter transform: The transform applied to every point.
    /// - Returns: The Core Graphics path.
    func cgPath(transform: CGAffineTransform = .identity) -> CGPath {
        let path = CGMutablePath()
        var hasCurrentPoint = false
        for segment in segments {
            switch segment {
            case .move(let point):
                path.move(to: point, transform: transform)
                hasCurrentPoint = true
            case .line(let point):
                if hasCurrentPoint {
                    path.addLine(to: point, transform: transform)
                } else {
                    path.move(to: point, transform: transform)
                    hasCurrentPoint = true
                }
            case let .quad(control, point):
                guard hasCurrentPoint else { continue }
                path.addQuadCurve(to: point, control: control, transform: transform)
            case let .cubic(control1, control2, point):
                guard hasCurrentPoint else { continue }
                path.addCurve(to: point, control1: control1, control2: control2, transform: transform)
            case .close:
                if hasCurrentPoint { path.closeSubpath() }
            }
        }
        return path
    }

    /// The tight bounding box of the geometry (control points excluded), or `.null` when
    /// the path is empty. A path made of a single point has a zero-size box at that point.
    var boundingBox: CGRect {
        guard !segments.isEmpty else { return .null }
        let box = cgPath().boundingBoxOfPath
        if box.isNull, case .move(let point) = segments.first {
            return CGRect(origin: point, size: .zero)
        }
        return box
    }
}
