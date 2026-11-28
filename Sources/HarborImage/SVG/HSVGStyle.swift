//
//  HSVGStyle.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// The computed style of an element while rendering: the inherited properties come from the
/// parent, the others start at their initial value. Invalid values are ignored, as CSS does.
struct HSVGStyle {
    /// A fill or stroke paint.
    enum Paint: Equatable {
        /// Nothing is painted.
        case none
        /// A color.
        case color(HSVGColor)
        /// The `color` property.
        case currentColor
        /// A paint server (`url(#id)`), with the paint used when it cannot be resolved.
        case reference(String, fallback: HSVGColor?)
    }

    // Inherited properties.

    /// The fill paint.
    var fill: Paint = .color(.black)
    /// The fill opacity.
    var fillOpacity = 1.0
    /// The fill rule.
    var fillRule: CGPathFillRule = .winding
    /// The stroke paint.
    var stroke: Paint = .none
    /// The stroke opacity.
    var strokeOpacity = 1.0
    /// The stroke width.
    var strokeWidth = HSVGLength(value: 1, unit: "")
    /// The line cap.
    var lineCap: CGLineCap = .butt
    /// The line join.
    var lineJoin: CGLineJoin = .miter
    /// The miter limit.
    var miterLimit = 4.0
    /// The dash lengths, empty for a solid stroke.
    var dashArray: [HSVGLength] = []
    /// The dash offset.
    var dashOffset = HSVGLength(value: 0, unit: "")
    /// The `color` property, used by `currentColor`.
    var color = HSVGColor.black
    /// Whether shapes are painted (`visibility`).
    var isVisible = true
    /// The clip rule of shapes inside a `clipPath`.
    var clipRule: CGPathFillRule = .winding

    // Properties that are not inherited.

    /// The group opacity.
    var opacity = 1.0
    /// Whether the element is rendered at all (`display`).
    var isDisplayed = true
    /// The id of the clip path, if any.
    var clipPath: String?
}

// MARK: - Cascade

extension HSVGStyle {
    /// The style of a child: the inherited properties of this style, the others reset, then the
    /// child's declared properties applied.
    /// - Parameter properties: The child's declared properties.
    /// - Throws: `.unsupported` for filters, masks, markers, a `paint-order` other than the
    ///   default, `vector-effect`, and the CSS `transform` and `transform-origin` properties.
    func child(applying properties: [String: String]) throws(HSVGError) -> HSVGStyle {
        var style = self
        style.opacity = 1
        style.isDisplayed = true
        style.clipPath = nil
        for (property, rawValue) in properties {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value == "inherit" {
                style.inherit(property, from: self)
                continue
            }
            try style.apply(property, value)
        }
        return style
    }

    /// Copies one property from the parent (`inherit`).
    /// - Parameters:
    ///   - property: The property.
    ///   - parent: The parent style.
    private mutating func inherit(_ property: String, from parent: HSVGStyle) {
        switch property {
        case "opacity": opacity = parent.opacity
        case "display": isDisplayed = parent.isDisplayed
        case "clip-path": clipPath = parent.clipPath
        default: break // The other properties are already inherited.
        }
    }

    /// Applies one declared property.
    /// - Parameters:
    ///   - property: The property.
    ///   - value: The value.
    private mutating func apply(_ property: String, _ value: String) throws(HSVGError) {
        switch property {
        case "fill": if let paint = Self.paint(value) { fill = paint }
        case "stroke": if let paint = Self.paint(value) { stroke = paint }
        case "fill-opacity": if let number = Self.fraction(value) { fillOpacity = number }
        case "stroke-opacity": if let number = Self.fraction(value) { strokeOpacity = number }
        case "opacity": if let number = Self.fraction(value) { opacity = number }
        case "fill-rule": if let rule = Self.fillRule(value) { fillRule = rule }
        case "clip-rule": if let rule = Self.fillRule(value) { clipRule = rule }
        case "stroke-width": if let length = HSVGLength.parse(value), length.value >= 0 { strokeWidth = length }
        case "stroke-linecap":
            switch value {
            case "butt": lineCap = .butt
            case "round": lineCap = .round
            case "square": lineCap = .square
            default: break
            }
        case "stroke-linejoin":
            switch value {
            case "miter", "miter-clip", "arcs": lineJoin = .miter
            case "round": lineJoin = .round
            case "bevel": lineJoin = .bevel
            default: break
            }
        case "stroke-miterlimit": if let number = Double(value), number >= 1 { miterLimit = number }
        case "stroke-dasharray": if let dashes = Self.dashArray(value) { dashArray = dashes }
        case "stroke-dashoffset": if let length = HSVGLength.parse(value) { dashOffset = length }
        case "color": if let parsed = HSVGColor.parse(value) { color = parsed }
        case "display": isDisplayed = value != "none"
        case "visibility": isVisible = value == "visible"
        case "clip-path": clipPath = value == "none" ? nil : Self.referenceID(value)
        case "filter", "mask", "marker", "marker-start", "marker-mid", "marker-end":
            if value != "none" { throw .unsupported(property) }
        case "transform", "transform-origin":
            throw .unsupported("CSS \(property)")
        case "paint-order":
            if value != "normal", value != "fill", value != "fill stroke", value != "fill stroke markers" {
                throw .unsupported("paint-order: \(value)")
            }
        case "vector-effect":
            if value != "none" { throw .unsupported("vector-effect: \(value)") }
        default:
            break
        }
    }
}

// MARK: - Values

extension HSVGStyle {
    /// Parses a paint: `none`, `currentColor`, a color, or `url(#id)` with an optional fallback.
    /// - Parameter value: The value.
    static func paint(_ value: String) -> Paint? {
        if value == "none" { return Paint.none }
        if value.lowercased() == "currentcolor" { return .currentColor }
        if value.hasPrefix("url(") {
            guard let close = value.firstIndex(of: ")"), let id = referenceID(String(value[...close])) else { return nil }
            let fallbackText = value[value.index(after: close)...].trimmingCharacters(in: .whitespaces)
            return .reference(id, fallback: fallbackText.isEmpty || fallbackText == "none" ? nil : HSVGColor.parse(fallbackText))
        }
        return HSVGColor.parse(value).map { .color($0) }
    }

    /// The id of a `url(#id)` reference.
    /// - Parameter value: The value.
    static func referenceID(_ value: String) -> String? {
        guard value.hasPrefix("url("), let close = value.firstIndex(of: ")") else { return nil }
        var inner = value[value.index(value.startIndex, offsetBy: 4)..<close].trimmingCharacters(in: .whitespaces)
        inner = inner.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard inner.hasPrefix("#"), inner.count > 1 else { return nil }
        return String(inner.dropFirst())
    }

    /// Parses a number or a percentage into `0...1`.
    /// - Parameter value: The value.
    static func fraction(_ value: String) -> Double? {
        let number = value.hasSuffix("%") ? Double(value.dropLast()).map { $0 / 100 } : Double(value)
        return number.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil }
    }

    /// Parses `nonzero` or `evenodd`.
    /// - Parameter value: The value.
    private static func fillRule(_ value: String) -> CGPathFillRule? {
        switch value {
        case "nonzero": return .winding
        case "evenodd": return .evenOdd
        default: return nil
        }
    }

    /// Parses a dash array; `none`, negative or all-zero lists disable dashing.
    /// - Parameter value: The value.
    private static func dashArray(_ value: String) -> [HSVGLength]? {
        if value == "none" { return [] }
        let parts = value.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" || $0 == "\n" })
        let lengths = parts.compactMap { HSVGLength.parse(String($0)) }
        guard lengths.count == parts.count else { return nil }
        guard lengths.allSatisfy({ $0.value >= 0 }), lengths.contains(where: { $0.value > 0 }) else { return [] }
        return lengths.count % 2 == 1 ? lengths + lengths : lengths
    }
}
