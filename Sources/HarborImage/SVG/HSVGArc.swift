//
//  HSVGArc.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// An elliptical arc in endpoint parameterization (the arguments of the `A` path command),
/// converted to cubic Bézier curves with the endpoint-to-center conversion of the SVG
/// specification (implementation notes, sections F.6.5 and F.6.6).
struct HSVGArc {
    /// The current point, where the arc starts.
    let start: CGPoint
    /// Where the arc ends.
    let end: CGPoint
    /// The ellipse radii, before the out-of-range correction.
    let radii: CGSize
    /// The rotation of the ellipse's x-axis, in degrees.
    let rotation: Double
    /// Whether the arc spans more than 180 degrees.
    let largeArc: Bool
    /// Whether the arc runs in the positive-angle direction.
    let sweep: Bool
}

// MARK: - Conversion

extension HSVGArc {
    /// The center parameterization of an arc.
    private struct CenterForm {
        /// The ellipse center.
        let center: CGPoint
        /// The corrected horizontal radius.
        let rx: Double
        /// The corrected vertical radius.
        let ry: Double
        /// The angle where the arc starts, in radians.
        let startAngle: Double
        /// The signed angle the arc spans, in radians.
        let sweepAngle: Double
    }

    /// Appends the arc to `path` as cubic curves of at most 90 degrees each. An arc whose
    /// endpoints coincide is omitted, and one with a zero radius is a straight line.
    /// - Parameter path: The path to extend; its current point must be `start`.
    func append(to path: inout HSVGPath) {
        if start == end { return }
        guard radii.width != 0, radii.height != 0, let form = centerForm() else {
            path.line(to: end)
            return
        }
        // At most 90° per cubic; the tolerance keeps an exact 90° multiple from getting one more.
        let segmentCount = max(1, Int((abs(form.sweepAngle) / (.pi / 2) - 1e-9).rounded(.up)))
        let delta = form.sweepAngle / Double(segmentCount)
        // Distance of the control points along the tangent, per unit radius.
        let handle = 4.0 / 3.0 * tan(delta / 4)
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        /// Maps a point on the unit circle to the rotated, scaled ellipse.
        func map(_ x: Double, _ y: Double) -> CGPoint {
            let ex = form.rx * x
            let ey = form.ry * y
            return CGPoint(x: form.center.x + cosPhi * ex - sinPhi * ey,
                           y: form.center.y + sinPhi * ex + cosPhi * ey)
        }
        var angle = form.startAngle
        for index in 0..<segmentCount {
            let next = angle + delta
            let cos1 = cos(angle)
            let sin1 = sin(angle)
            let cos2 = cos(next)
            let sin2 = sin(next)
            let control1 = map(cos1 - handle * sin1, sin1 + handle * cos1)
            let control2 = map(cos2 + handle * sin2, sin2 - handle * cos2)
            // The last segment ends exactly at the requested endpoint, without rounding drift.
            let point = index == segmentCount - 1 ? end : map(cos2, sin2)
            path.cubic(to: point, control1: control1, control2: control2)
            angle = next
        }
    }

    /// Converts the endpoint parameterization to the center parameterization (F.6.5),
    /// scaling radii that are too small to reach the endpoint (F.6.6).
    /// - Returns: The center form, or `nil` when the arc degenerates.
    private func centerForm() -> CenterForm? {
        var rx = abs(Double(radii.width))
        var ry = abs(Double(radii.height))
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let x1 = Double(start.x)
        let y1 = Double(start.y)
        let x2 = Double(end.x)
        let y2 = Double(end.y)
        // Step 1: compute (x1', y1').
        let dx = (x1 - x2) / 2
        let dy = (y1 - y2) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        // F.6.6: scale the radii up when they cannot span the endpoints.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = lambda.squareRoot()
            rx *= scale
            ry *= scale
        }
        // Step 2: compute (cx', cy').
        let rx2 = rx * rx
        let ry2 = ry * ry
        let numerator = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p
        let denominator = rx2 * y1p * y1p + ry2 * x1p * x1p
        guard denominator > 0 else { return nil }
        var coefficient = (max(0, numerator) / denominator).squareRoot()
        if largeArc == sweep {
            coefficient = -coefficient
        }
        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        // Step 3: compute (cx, cy) from (cx', cy').
        let cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2
        // Step 4: compute the start angle and the swept angle.
        let ux = (x1p - cxp) / rx
        let uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx
        let vy = (-y1p - cyp) / ry
        let startAngle = atan2(uy, ux)
        var sweepAngle = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        if !sweep, sweepAngle > 0 {
            sweepAngle -= 2 * .pi
        } else if sweep, sweepAngle < 0 {
            sweepAngle += 2 * .pi
        }
        guard sweepAngle.isFinite, startAngle.isFinite else { return nil }
        return CenterForm(center: CGPoint(x: cx, y: cy), rx: rx, ry: ry, startAngle: startAngle, sweepAngle: sweepAngle)
    }
}
