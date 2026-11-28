//
//  HSVGRenderer.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// Draws a parsed SVG document into a Core Graphics context whose user space has the origin at
/// the top left. One renderer per render: it tracks the element, depth and work budgets, the
/// `use` recursion, and caches the geometry of every shape, which `use` may draw many times.
final class HSVGRenderer {
    /// Deepest nesting rendered (groups, `use` instances, nested viewports); deeper fails with
    /// `.tooLarge` instead of overflowing the stack.
    static let maxDepth = 64
    /// Most path segments drawn in one render, counting every `use` instance; past it the
    /// render fails with `.tooLarge`, so a small document cannot keep the CPU busy for seconds.
    static let maxWork = 2_000_000

    /// Elements that are outside the supported subset when rendered or referenced.
    static let unsupportedElements: Set<String> = [
        "text", "tspan", "textPath", "image", "foreignObject", "pattern", "filter", "mask", "marker",
        "animate", "animateMotion", "animateTransform", "animateColor", "set", "font", "glyph", "video", "audio", "iframe", "canvas",
    ]
    /// Elements that are never drawn directly.
    private static let nonRendering: Set<String> = [
        "defs", "symbol", "clipPath", "linearGradient", "radialGradient", "stop", "style", "title", "desc", "metadata",
    ]

    /// The context drawn into.
    private let context: CGContext
    /// The elements with an id.
    private let elements: [String: HSVGElement]
    /// The style sheet.
    private let styleSheet: HSVGStyleSheet
    /// Elements drawn so far, including `use` instances.
    private var drawnElements = 0
    /// The elements being instantiated by `use`, to detect cycles (`.malformed`).
    private var useStack: [ObjectIdentifier] = []
    /// The current nesting depth.
    private var depth = 0
    /// Path segments drawn so far.
    private var work = 0
    /// The geometry of each shape, by element and viewport.
    private var shapes: [HSVGGeometryKey: HSVGShape?] = [:]
    /// The bounding box of each element, by element and viewport.
    private var bounds: [HSVGGeometryKey: CGRect] = [:]

    /// Creates a renderer.
    /// - Parameters:
    ///   - context: The context, with the origin at the top left.
    ///   - elements: The elements with an id.
    ///   - styleSheet: The style sheet.
    init(context: CGContext, elements: [String: HSVGElement], styleSheet: HSVGStyleSheet) {
        self.context = context
        self.elements = elements
        self.styleSheet = styleSheet
    }
}

// MARK: - Elements

extension HSVGRenderer {
    /// Draws the children of the root `<svg>` (its viewport transform is already applied).
    /// - Parameters:
    ///   - root: The root element.
    ///   - viewport: The size percentages refer to.
    func renderRoot(_ root: HSVGElement, viewport: CGSize) throws(HSVGError) {
        let style = try HSVGStyle().child(applying: styleSheet.declaredProperties(of: root))
        guard style.isDisplayed else { return }
        // The root's own `transform` (SVG 2) applies inside its viewport mapping.
        try group(root, style: style, viewport: viewport) {
            for child in root.children {
                try render(child, parent: style, viewport: viewport)
            }
        }
    }

    /// Draws an element and its children.
    /// - Parameters:
    ///   - element: The element.
    ///   - parent: The parent's computed style.
    ///   - viewport: The size percentages refer to.
    private func render(_ element: HSVGElement, parent: HSVGStyle, viewport: CGSize) throws(HSVGError) {
        drawnElements += 1
        depth += 1
        defer { depth -= 1 }
        guard drawnElements <= HSVGXMLReader.maxElements, depth <= Self.maxDepth else { throw .tooLarge }
        if Self.unsupportedElements.contains(element.name) {
            throw .unsupported("<\(element.name)>")
        }
        guard !Self.nonRendering.contains(element.name) else { return }
        // Shapes do not render their children, but an animation inside one would change it.
        if let child = element.children.first(where: { Self.unsupportedElements.contains($0.name) }) {
            throw .unsupported("<\(child.name)>")
        }

        let style = try parent.child(applying: styleSheet.declaredProperties(of: element))
        guard style.isDisplayed else { return }

        switch element.name {
        case "g", "a":
            try group(element, style: style, viewport: viewport) {
                for child in element.children {
                    try render(child, parent: style, viewport: viewport)
                }
            }
        case "switch":
            if let first = element.children.first(where: { $0.name != "foreignObject" }) {
                try group(element, style: style, viewport: viewport) {
                    try render(first, parent: style, viewport: viewport)
                }
            }
        case "svg":
            try nestedViewport(element, style: style, viewport: viewport)
        case "use":
            try use(element, style: style, viewport: viewport)
        default:
            guard let shape = try resolvedShape(element, viewport: viewport) else { return }
            try group(element, style: style, viewport: viewport, bounds: shape.bounds) {
                try paint(shape, style: style, viewport: viewport)
            }
        }
    }

    /// Runs `body` with the element's transform, clip path and group opacity applied.
    /// - Parameters:
    ///   - element: The element.
    ///   - style: Its computed style.
    ///   - viewport: The size percentages refer to.
    ///   - appliesTransform: Whether the `transform` attribute applies (not on `<svg>`).
    ///   - bounds: The element's bounding box, when already known.
    ///   - body: The drawing.
    private func group(_ element: HSVGElement, style: HSVGStyle, viewport: CGSize, appliesTransform: Bool = true, bounds: CGRect? = nil, _ body: () throws -> Void) throws(HSVGError) {
        context.saveGState()
        defer { context.restoreGState() }
        if appliesTransform {
            context.concatenate(try HSVGTransform.parse(element.attributes["transform"]))
        }
        if let clipID = style.clipPath {
            try applyClipPath(clipID, bounds: bounds ?? geometryBounds(element, viewport: viewport), viewport: viewport)
        }
        guard style.opacity < 1 else {
            try Self.run(body)
            return
        }
        guard style.opacity > 0 else { return }
        context.setAlpha(style.opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }
        try Self.run(body)
    }

    /// Runs a drawing closure, keeping its `HSVGError`.
    /// - Parameter body: The drawing.
    private static func run(_ body: () throws -> Void) throws(HSVGError) {
        do {
            try body()
        } catch let error as HSVGError {
            throw error
        } catch {
            throw .malformed(String(describing: error))
        }
    }

    /// Draws a `use` element: the referenced element, moved by `x` and `y`.
    /// - Parameters:
    ///   - element: The `use` element.
    ///   - style: Its computed style, inherited by the instance.
    ///   - viewport: The size percentages refer to.
    private func use(_ element: HSVGElement, style: HSVGStyle, viewport: CGSize) throws(HSVGError) {
        guard let href = element.href, !href.isEmpty else { return }
        guard href.hasPrefix("#") else { throw .unsafe("external reference \(href)") }
        guard let target = elements[String(href.dropFirst())] else { return }
        let identifier = ObjectIdentifier(target)
        guard !useStack.contains(identifier) else { throw .malformed("<use> cycle") }
        useStack.append(identifier)
        defer { useStack.removeLast() }

        let x = HSVGLength.parse(element.attributes["x"])?.resolved(viewport: viewport, axis: .horizontal) ?? 0
        let y = HSVGLength.parse(element.attributes["y"])?.resolved(viewport: viewport, axis: .vertical) ?? 0
        try group(element, style: style, viewport: viewport) {
            context.translateBy(x: x, y: y)
            switch target.name {
            case "symbol", "svg":
                let symbolStyle = try style.child(applying: styleSheet.declaredProperties(of: target))
                guard symbolStyle.isDisplayed else { return }
                try nestedViewport(target, style: symbolStyle, viewport: viewport, sizeSource: element)
            default:
                try render(target, parent: style, viewport: viewport)
            }
        }
    }

    /// Draws a nested `<svg>` or an instantiated `<symbol>`: its own viewport, clipped, with its
    /// `viewBox` mapping.
    /// - Parameters:
    ///   - element: The element establishing the viewport, carrying `viewBox` and the content.
    ///   - style: The element's computed style.
    ///   - viewport: The parent viewport size.
    ///   - sizeSource: The `use` instantiating a symbol or an `<svg>`: its `width` and `height`
    ///     win over the element's own. Default: `nil`.
    private func nestedViewport(_ element: HSVGElement, style: HSVGStyle, viewport: CGSize, sizeSource: HSVGElement? = nil) throws(HSVGError) {
        let overflow = styleSheet.declaredProperties(of: element)["overflow"]?.trimmingCharacters(in: .whitespaces)
        if overflow == "visible" || overflow == "auto" {
            throw .unsupported("overflow: \(overflow ?? "")")
        }
        let isNestedSVG = element.name == "svg" && sizeSource == nil
        let x = isNestedSVG ? HSVGLength.parse(element.attributes["x"])?.resolved(viewport: viewport, axis: .horizontal) ?? 0 : 0
        let y = isNestedSVG ? HSVGLength.parse(element.attributes["y"])?.resolved(viewport: viewport, axis: .vertical) ?? 0 : 0
        /// The size from the `use` element, else from the element itself, else the viewport.
        func size(_ name: String, _ axis: HSVGLength.Axis, _ fallback: CGFloat) -> CGFloat {
            let length = sizeSource.flatMap { HSVGLength.parse($0.attributes[name]) } ?? HSVGLength.parse(element.attributes[name])
            return length?.resolved(viewport: viewport, axis: axis) ?? fallback
        }
        let width = size("width", .horizontal, viewport.width)
        let height = size("height", .vertical, viewport.height)
        guard width > 0, height > 0 else { return }

        let frame = CGRect(x: x, y: y, width: width, height: height)
        let viewBox = HSVGViewBox.parse(element)
        try group(element, style: style, viewport: viewport, appliesTransform: !isNestedSVG && element.name != "symbol", bounds: frame) {
            context.clip(to: frame)
            if let viewBox {
                context.concatenate(viewBox.transform(into: frame))
            } else {
                context.translateBy(x: x, y: y)
            }
            let innerViewport = viewBox?.rect.size ?? frame.size
            for child in element.children {
                try render(child, parent: style, viewport: innerViewport)
            }
        }
    }
}

// MARK: - Shapes

extension HSVGRenderer {
    /// The geometry of a basic shape or a path, or `nil` for anything else (and for shapes that
    /// draw nothing, such as a rectangle without width).
    /// - Parameters:
    ///   - element: The element.
    ///   - viewport: The size percentages refer to.
    func shape(_ element: HSVGElement, viewport: CGSize) throws(HSVGError) -> HSVGPath? {
        func length(_ name: String, _ axis: HSVGLength.Axis) -> CGFloat? {
            HSVGLength.parse(element.attributes[name])?.resolved(viewport: viewport, axis: axis)
        }
        switch element.name {
        case "rect":
            let width = length("width", .horizontal) ?? 0
            let height = length("height", .vertical) ?? 0
            guard width > 0, height > 0 else { return nil }
            var rx = length("rx", .horizontal)
            var ry = length("ry", .vertical)
            if rx == nil || rx! < 0 { rx = ry }
            if ry == nil || ry! < 0 { ry = rx }
            let radii = CGSize(width: min(max(rx ?? 0, 0), width / 2), height: min(max(ry ?? 0, 0), height / 2))
            return HSVGPath.rect(CGRect(x: length("x", .horizontal) ?? 0, y: length("y", .vertical) ?? 0, width: width, height: height), radii: radii)
        case "circle":
            let radius = length("r", .other) ?? 0
            guard radius > 0 else { return nil }
            return HSVGPath.ellipse(center: CGPoint(x: length("cx", .horizontal) ?? 0, y: length("cy", .vertical) ?? 0), radii: CGSize(width: radius, height: radius))
        case "ellipse":
            var rx = length("rx", .horizontal)
            var ry = length("ry", .vertical)
            if rx == nil { rx = ry }
            if ry == nil { ry = rx }
            guard let rx, let ry, rx > 0, ry > 0 else { return nil }
            return HSVGPath.ellipse(center: CGPoint(x: length("cx", .horizontal) ?? 0, y: length("cy", .vertical) ?? 0), radii: CGSize(width: rx, height: ry))
        case "line":
            var path = HSVGPath()
            path.move(to: CGPoint(x: length("x1", .horizontal) ?? 0, y: length("y1", .vertical) ?? 0))
            path.line(to: CGPoint(x: length("x2", .horizontal) ?? 0, y: length("y2", .vertical) ?? 0))
            return path
        case "polyline", "polygon":
            guard let numbers = HSVGScanner.numberList(element.attributes["points"] ?? ""), numbers.count >= 2 else { return nil }
            var path = HSVGPath()
            for index in stride(from: 0, to: numbers.count - 1, by: 2) {
                let point = CGPoint(x: numbers[index], y: numbers[index + 1])
                if index == 0 { path.move(to: point) } else { path.line(to: point) }
            }
            if element.name == "polygon" { path.close() }
            return path
        case "path":
            let path = HSVGPathParser.parse(element.attributes["d"] ?? "")
            return path.isEmpty ? nil : path
        default:
            return nil
        }
    }

    /// The geometry of a shape, built once per element and viewport: `use` can draw the same
    /// shape many times, and clip paths and bounding boxes read it again.
    /// - Parameters:
    ///   - element: The element.
    ///   - viewport: The size percentages refer to.
    /// - Returns: The shape, or `nil` for an element that is not a shape or draws nothing.
    private func resolvedShape(_ element: HSVGElement, viewport: CGSize) throws(HSVGError) -> HSVGShape? {
        let key = HSVGGeometryKey(element: element, viewport: viewport)
        if let cached = shapes[key] {
            return cached
        }
        let resolved = try shape(element, viewport: viewport).map(HSVGShape.init)
        shapes[key] = .some(resolved)
        return resolved
    }

    /// Counts path segments toward the work budget.
    /// - Parameter segments: The segments about to be drawn.
    /// - Throws: `.tooLarge` past `maxWork`.
    private func spend(_ segments: Int) throws(HSVGError) {
        work += segments
        guard work <= Self.maxWork else { throw .tooLarge }
    }

    /// Fills and strokes a shape.
    /// - Parameters:
    ///   - shape: The shape.
    ///   - style: Its computed style.
    ///   - viewport: The size percentages refer to.
    private func paint(_ shape: HSVGShape, style: HSVGStyle, viewport: CGSize) throws(HSVGError) {
        guard style.isVisible else { return }
        let path = shape.path
        let bounds = shape.bounds

        if style.fill != .none {
            try spend(shape.segmentCount)
            try draw(stroke: false, style: style, bounds: bounds, viewport: viewport) { solid in
                context.addPath(path)
                if solid {
                    context.fillPath(using: style.fillRule)
                } else {
                    context.clip(using: style.fillRule)
                }
            }
        }

        let width = style.strokeWidth.resolved(viewport: viewport, axis: .other)
        guard style.stroke != .none, width > 0 else { return }
        try spend(shape.segmentCount)
        context.setLineWidth(width)
        context.setLineCap(style.lineCap)
        context.setLineJoin(style.lineJoin)
        context.setMiterLimit(style.miterLimit)
        let dashes = style.dashArray.map { $0.resolved(viewport: viewport, axis: .other) }
        context.setLineDash(phase: dashes.isEmpty ? 0 : style.dashOffset.resolved(viewport: viewport, axis: .other), lengths: dashes)
        try draw(stroke: true, style: style, bounds: bounds, viewport: viewport) { solid in
            context.addPath(path)
            if solid {
                context.strokePath()
            } else {
                context.replacePathWithStrokedPath()
                context.clip()
            }
        }
    }

    /// Paints with a color or a gradient. `operation(true)` draws with the color set; for a
    /// gradient `operation(false)` must clip to the painted area, then the gradient is drawn.
    /// - Parameters:
    ///   - stroke: Whether the stroke paint is used, rather than the fill.
    ///   - style: The computed style: the paint, its opacity and `currentColor`.
    ///   - bounds: The shape's bounding box (for `objectBoundingBox` gradients).
    ///   - viewport: The size percentages refer to.
    ///   - operation: Fills, strokes or clips.
    private func draw(stroke: Bool, style: HSVGStyle, bounds: CGRect, viewport: CGSize, _ operation: (Bool) -> Void) throws(HSVGError) {
        let paint = stroke ? style.stroke : style.fill
        let opacity = stroke ? style.strokeOpacity : style.fillOpacity
        var color: HSVGColor?
        switch paint {
        case .none:
            return
        case .color(let value):
            color = value
        case .currentColor:
            color = style.color
        case .reference(let id, let fallback):
            if let server = elements[id], server.name == "linearGradient" || server.name == "radialGradient" {
                context.saveGState()
                defer { context.restoreGState() }
                operation(false)
                try HSVGGradient(element: server, elements: elements, styleSheet: styleSheet, currentColor: style.color)
                    .draw(in: context, bounds: bounds, viewport: viewport, opacity: opacity)
                return
            }
            if let server = elements[id], Self.unsupportedElements.contains(server.name) {
                throw .unsupported("<\(server.name)> paint")
            }
            color = fallback
        }
        guard let color else { return }
        context.setFillColor(color.cgColor(opacity: opacity))
        context.setStrokeColor(color.cgColor(opacity: opacity))
        operation(true)
    }
}

// MARK: - Clipping

extension HSVGRenderer {
    /// Clips to a `clipPath`: the union of its shapes (and `use` of shapes), each filled with its
    /// own `clip-rule`. Other children (groups, for example) are skipped, as the SVG spec allows
    /// only shapes, text and `use` there. A missing reference does not clip; an empty clip path
    /// hides the element.
    /// - Parameters:
    ///   - id: The id of the `clipPath`.
    ///   - bounds: The bounding box of the clipped element.
    ///   - viewport: The size percentages refer to.
    private func applyClipPath(_ id: String, bounds: CGRect, viewport: CGSize) throws(HSVGError) {
        guard let clip = elements[id], clip.name == "clipPath" else { return }
        var transform = try HSVGTransform.parse(clip.attributes["transform"])
        if clip.attributes["clipPathUnits"] == "objectBoundingBox" {
            guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else {
                context.clip(to: .zero)
                return
            }
            transform = CGAffineTransform(a: bounds.width, b: 0, c: 0, d: bounds.height, tx: bounds.minX, ty: bounds.minY).concatenating(transform)
        }

        var parts: [(path: CGPath, rule: CGPathFillRule)] = []
        let clipStyle = try HSVGStyle().child(applying: styleSheet.declaredProperties(of: clip))
        for child in clip.children {
            var element = child
            var childTransform = try HSVGTransform.parse(child.attributes["transform"])
            if child.name == "use", let href = child.href, href.hasPrefix("#"), let target = elements[String(href.dropFirst())] {
                let x = HSVGLength.parse(child.attributes["x"])?.resolved(viewport: viewport, axis: .horizontal) ?? 0
                let y = HSVGLength.parse(child.attributes["y"])?.resolved(viewport: viewport, axis: .vertical) ?? 0
                childTransform = try HSVGTransform.parse(target.attributes["transform"])
                    .concatenating(CGAffineTransform(translationX: x, y: y))
                    .concatenating(childTransform)
                element = target
            }
            if Self.unsupportedElements.contains(element.name) {
                throw .unsupported("<\(element.name)> in <clipPath>")
            }
            let style = try clipStyle.child(applying: styleSheet.declaredProperties(of: element))
            guard style.isDisplayed, style.isVisible, let shape = try resolvedShape(element, viewport: viewport) else { continue }
            try spend(shape.segmentCount)
            var placement = childTransform.concatenating(transform)
            guard let placed = shape.path.copy(using: &placement) else { continue }
            parts.append((placed, style.clipRule))
        }
        guard let first = parts.first else {
            context.clip(to: .zero)
            return
        }
        guard parts.count > 1 else {
            context.addPath(first.path)
            context.clip(using: first.rule)
            return
        }
        // Several shapes: each is filled with its own rule, then they are united, so shapes that
        // wind in opposite directions do not cancel each other out.
        guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else {
            throw .unsupported("<clipPath> with several shapes before iOS 16")
        }
        let union = parts.dropFirst().reduce(first.path.normalized(using: first.rule)) { result, part in
            result.union(part.path.normalized(using: part.rule))
        }
        context.addPath(union)
        context.clip()
    }

    /// The bounding box of an element's geometry in its own user space, children and `use`
    /// instances included; cached per element and viewport.
    /// - Parameters:
    ///   - element: The element.
    ///   - viewport: The size percentages refer to.
    private func geometryBounds(_ element: HSVGElement, viewport: CGSize) -> CGRect {
        let key = HSVGGeometryKey(element: element, viewport: viewport)
        if let cached = bounds[key] {
            return cached
        }
        let result = computeBounds(element, viewport: viewport, depth: 0)
        bounds[key] = result
        return result
    }

    /// Computes the bounding box of an element (see `geometryBounds(_:viewport:)`).
    /// - Parameters:
    ///   - element: The element.
    ///   - viewport: The size percentages refer to.
    ///   - depth: The nesting depth so far; past `maxDepth` the box is empty.
    private func computeBounds(_ element: HSVGElement, viewport: CGSize, depth: Int) -> CGRect {
        guard depth <= Self.maxDepth else { return .null }
        if let shape = try? resolvedShape(element, viewport: viewport) {
            return shape.bounds
        }
        if element.name == "use" {
            guard let href = element.href, href.hasPrefix("#"), let target = elements[String(href.dropFirst())] else { return .null }
            let x = HSVGLength.parse(element.attributes["x"])?.resolved(viewport: viewport, axis: .horizontal) ?? 0
            let y = HSVGLength.parse(element.attributes["y"])?.resolved(viewport: viewport, axis: .vertical) ?? 0
            if target.name == "symbol" || target.name == "svg" {
                let width = HSVGLength.parse(element.attributes["width"] ?? target.attributes["width"])?.resolved(viewport: viewport, axis: .horizontal) ?? viewport.width
                let height = HSVGLength.parse(element.attributes["height"] ?? target.attributes["height"])?.resolved(viewport: viewport, axis: .vertical) ?? viewport.height
                return CGRect(x: x, y: y, width: width, height: height)
            }
            let transform = (try? HSVGTransform.parse(target.attributes["transform"])) ?? .identity
            let targetBounds = computeBounds(target, viewport: viewport, depth: depth + 1)
            return targetBounds.isNull ? .null : targetBounds.applying(transform.concatenating(CGAffineTransform(translationX: x, y: y)))
        }
        var result = CGRect.null
        for child in element.children where !Self.nonRendering.contains(child.name) {
            let transform = (try? HSVGTransform.parse(child.attributes["transform"])) ?? .identity
            let childBounds = computeBounds(child, viewport: viewport, depth: depth + 1)
            if !childBounds.isNull {
                result = result.union(childBounds.applying(transform))
            }
        }
        return result
    }
}

// MARK: - Shape Cache

/// A shape ready to draw: its path, bounding box and size in segments (for the work budget).
private struct HSVGShape {
    /// The path.
    let path: CGPath
    /// The tight bounding box.
    let bounds: CGRect
    /// The number of segments, the cost of drawing it.
    let segmentCount: Int

    /// Builds the shape of a parsed path.
    /// - Parameter geometry: The parsed path.
    init(_ geometry: HSVGPath) {
        self.path = geometry.cgPath()
        self.bounds = geometry.boundingBox
        self.segmentCount = max(1, geometry.segments.count)
    }
}

/// Identifies a geometry: the element and the viewport its percentages resolve against.
private struct HSVGGeometryKey: Hashable {
    /// The element.
    let element: ObjectIdentifier
    /// The viewport width.
    let width: CGFloat
    /// The viewport height.
    let height: CGFloat

    /// Creates a key.
    /// - Parameters:
    ///   - element: The element.
    ///   - viewport: The viewport.
    init(element: HSVGElement, viewport: CGSize) {
        self.element = ObjectIdentifier(element)
        self.width = viewport.width
        self.height = viewport.height
    }
}
