//
//  HSVGLength.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// An SVG length: a number with an optional unit, resolved to user units (CSS pixels).
struct HSVGLength: Sendable, Equatable {
    /// The number.
    let value: Double
    /// The unit, lowercased (`""`, `px`, `pt`, `%`, ...).
    let unit: String
}

// MARK: - Parsing

extension HSVGLength {
    /// Which viewport dimension a percentage refers to.
    enum Axis {
        /// The viewport width.
        case horizontal
        /// The viewport height.
        case vertical
        /// The normalized diagonal, for radii and stroke widths.
        case other
    }

    /// Parses a length.
    /// - Parameter text: The length text.
    /// - Returns: The length, or `nil` when the text is not one.
    static func parse(_ text: String?) -> HSVGLength? {
        guard let text else { return nil }
        var scanner = HSVGScanner(text)
        scanner.skipWhitespace()
        guard let number = scanner.scanNumber() else { return nil }
        let unit = scanner.scanUnit()
        scanner.skipWhitespace()
        guard scanner.isAtEnd, ["", "px", "pt", "pc", "mm", "cm", "in", "em", "rem", "ex", "vw", "vh", "vmin", "vmax", "%"].contains(unit) else { return nil }
        return HSVGLength(value: number, unit: unit)
    }

    /// The length in user units: `em` and `rem` are 16, `ex` is 8, `vw`, `vh`, `vmin` and
    /// `vmax` and percentages refer to the viewport.
    /// - Parameters:
    ///   - viewport: The viewport, for percentages.
    ///   - axis: Which viewport dimension a percentage refers to.
    func resolved(viewport: CGSize, axis: Axis) -> CGFloat {
        switch unit {
        case "pt": return value * 4 / 3
        case "pc": return value * 16
        case "mm": return value * 96 / 25.4
        case "cm": return value * 96 / 2.54
        case "in": return value * 96
        case "em": return value * 16
        case "ex": return value * 8
        case "rem": return value * 16
        case "vw": return value / 100 * viewport.width
        case "vh": return value / 100 * viewport.height
        case "vmin": return value / 100 * min(viewport.width, viewport.height)
        case "vmax": return value / 100 * max(viewport.width, viewport.height)
        case "%":
            switch axis {
            case .horizontal: return value / 100 * viewport.width
            case .vertical: return value / 100 * viewport.height
            case .other: return value / 100 * ((viewport.width * viewport.width + viewport.height * viewport.height) / 2).squareRoot()
            }
        default:
            return value
        }
    }

    /// Whether the length is a percentage.
    var isPercentage: Bool {
        unit == "%"
    }
}
