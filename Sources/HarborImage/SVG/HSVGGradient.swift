//
//  HSVGGradient.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// A `linearGradient` or `radialGradient` resolved through its `href` chain (attributes and stops
/// missing on a gradient come from the one it references). Only `spreadMethod="pad"` is supported.
struct HSVGGradient {
    /// A color stop.
    struct Stop {
        /// The offset in `0...1`.
        let offset: CGFloat
        /// The color, with the stop opacity applied.
        let color: HSVGColor
    }

    /// The gradient element.
    private let element: HSVGElement
    /// The gradient and the ones it references, nearest first (at most 16; a cycle stops it).
    private let chain: [HSVGElement]
    /// The stops.
    private let stops: [Stop]

    /// Resolves a gradient.
    /// - Parameters:
    ///   - element: The gradient element.
    ///   - elements: The elements with an id.
    ///   - styleSheet: The style sheet, for stop colors.
    ///   - currentColor: The `color` of the painted element, for `currentColor` stops.
    /// - Throws: `.unsupported` for `reflect` and `repeat` spread methods and for animations
    ///   inside the gradient or its stops.
    init(element: HSVGElement, elements: [String: HSVGElement], styleSheet: HSVGStyleSheet, currentColor: HSVGColor) throws(HSVGError) {
        var chain = [element]
        while chain.count < 16, let href = chain.last?.href, href.hasPrefix("#"),
              let next = elements[String(href.dropFirst())],
              next.name == "linearGradient" || next.name == "radialGradient",
              !chain.contains(where: { $0 === next }) {
            chain.append(next)
        }
        self.element = element
        self.chain = chain

        for gradient in chain {
            if let animation = gradient.children.first(where: { HSVGRenderer.unsupportedElements.contains($0.name) })
                ?? gradient.children.flatMap(\.children).first(where: { HSVGRenderer.unsupportedElements.contains($0.name) }) {
                throw .unsupported("<\(animation.name)> in a gradient")
            }
        }
        let stopElements = chain.first(where: { $0.children.contains { $0.name == "stop" } })?.children.filter { $0.name == "stop" } ?? []
        var stops: [Stop] = []
        var lastOffset: CGFloat = 0
        for stop in stopElements {
            let properties = styleSheet.declaredProperties(of: stop)
            let offsetText = stop.attributes["offset"] ?? "0"
            let offset = CGFloat(HSVGStyle.fraction(offsetText.trimmingCharacters(in: .whitespaces)) ?? 0)
            lastOffset = max(lastOffset, offset)
            let colorText = properties["stop-color"]?.trimmingCharacters(in: .whitespaces) ?? "black"
            var color = colorText.lowercased() == "currentcolor" ? currentColor : HSVGColor.parse(colorText) ?? .black
            color.alpha *= HSVGStyle.fraction(properties["stop-opacity"]?.trimmingCharacters(in: .whitespaces) ?? "1") ?? 1
            stops.append(Stop(offset: lastOffset, color: color))
        }
        self.stops = stops

        if let spread = attribute("spreadMethod"), spread != "pad" {
            throw .unsupported("gradient spreadMethod \(spread)")
        }
    }
}

// MARK: - Drawing

extension HSVGGradient {
    /// Draws the gradient over the current clip.
    /// - Parameters:
    ///   - context: The context, clipped to the painted area.
    ///   - bounds: The bounding box of the painted shape.
    ///   - viewport: The size percentages refer to.
    ///   - opacity: The fill or stroke opacity.
    func draw(in context: CGContext, bounds: CGRect, viewport: CGSize, opacity: Double) throws(HSVGError) {
        guard let first = stops.first else { return }
        if stops.count == 1 {
            context.setFillColor(first.color.cgColor(opacity: opacity))
            context.fill(context.boundingBoxOfClipPath)
            return
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: colorSpace,
                                        colors: stops.map { $0.color.cgColor(opacity: opacity) } as CFArray,
                                        locations: stops.map(\.offset)) else {
            return
        }

        let usesBoundingBox = attribute("gradientUnits") != "userSpaceOnUse"
        if usesBoundingBox {
            guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return }
            context.concatenate(CGAffineTransform(a: bounds.width, b: 0, c: 0, d: bounds.height, tx: bounds.minX, ty: bounds.minY))
        }
        context.concatenate(try HSVGTransform.parse(attribute("gradientTransform")))

        let unitViewport = usesBoundingBox ? CGSize(width: 1, height: 1) : viewport
        func coordinate(_ name: String, _ fallback: String, _ axis: HSVGLength.Axis) -> CGFloat {
            guard let length = HSVGLength.parse(attribute(name) ?? fallback) else { return 0 }
            return length.resolved(viewport: unitViewport, axis: axis)
        }
        let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]

        if element.name == "linearGradient" {
            let start = CGPoint(x: coordinate("x1", "0%", .horizontal), y: coordinate("y1", "0%", .vertical))
            let end = CGPoint(x: coordinate("x2", "100%", .horizontal), y: coordinate("y2", "0%", .vertical))
            context.drawLinearGradient(gradient, start: start, end: end, options: options)
        } else {
            let center = CGPoint(x: coordinate("cx", "50%", .horizontal), y: coordinate("cy", "50%", .vertical))
            let radius = coordinate("r", "50%", .other)
            let focus = CGPoint(x: attribute("fx") == nil ? center.x : coordinate("fx", "50%", .horizontal),
                                y: attribute("fy") == nil ? center.y : coordinate("fy", "50%", .vertical))
            let focusRadius = coordinate("fr", "0%", .other)
            guard radius > 0 else {
                // A zero radius paints the area with the last stop's color.
                context.setFillColor((stops.last ?? first).color.cgColor(opacity: opacity))
                context.fill(context.boundingBoxOfClipPath)
                return
            }
            context.drawRadialGradient(gradient, startCenter: focus, startRadius: focusRadius, endCenter: center, endRadius: radius, options: options)
        }
    }

    /// An attribute of the gradient or, when missing, of the nearest gradient it references.
    /// - Parameter name: The attribute name.
    private func attribute(_ name: String) -> String? {
        chain.lazy.compactMap { $0.attributes[name] }.first
    }
}
