//
//  HSVGDocument.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// A parsed SVG document, immutable: parsed once, rendered at any size from any thread.
///
/// The renderer supports a documented subset of SVG 1.1 / SVG 2 (shapes, paths, transforms,
/// solid and gradient paints, strokes with dashes, group opacity, clip paths, `use`/`symbol`,
/// nested viewports and simple CSS). Anything outside it (text, filters, masks, patterns,
/// images, animation, markers) throws `.unsupported` instead of rendering wrong, and unsafe
/// content (entity bombs, external references, scripts) throws `.unsafe`.
struct HSVGDocument: Sendable {
    /// Largest raster rendered, in pixels.
    static let maxPixels: CGFloat = 100_000_000

    /// The root `<svg>` element.
    private let root: HSVGElement
    /// The elements with an id.
    private let elements: [String: HSVGElement]
    /// The style sheet.
    private let styleSheet: HSVGStyleSheet
    /// The root `viewBox`, if any.
    private let viewBox: HSVGViewBox?
    /// Size in points from width/height attributes, falling back to the viewBox size, then 300x150.
    let intrinsicSize: CGSize

    /// Parses SVG bytes and checks that the whole document can be rendered.
    /// - Parameter data: The SVG bytes.
    /// - Throws: `.malformed`, `.unsupported`, `.unsafe` or `.tooLarge`.
    init(data: Data) throws(HSVGError) {
        let root = try HSVGXMLReader.read(data)
        var elements: [String: HSVGElement] = [:]
        root.forEach { element in
            if let id = element.id, elements[id] == nil {
                elements[id] = element
            }
        }
        self.root = root
        self.elements = elements
        self.styleSheet = try HSVGStyleSheet.parse(root: root)
        self.viewBox = HSVGViewBox.parse(root)
        self.intrinsicSize = Self.intrinsicSize(of: root, viewBox: viewBox)

        // A render at the smallest size walks the same elements as a real one, so unsupported
        // and unsafe content fails here rather than at display time.
        _ = try render(pixelSize: CGSize(width: 1, height: 1))
    }

    /// Renders into a new premultiplied RGBA sRGB image of exactly `pixelSize` (each side at
    /// least 1), mapping the `viewBox` with the root's `preserveAspectRatio`. The background is
    /// transparent.
    /// - Parameter pixelSize: The output size in pixels.
    /// - Throws: `.tooLarge` above 100 megapixels or when the bitmap cannot be created, or the
    ///   errors of an unsupported document.
    func render(pixelSize: CGSize) throws(HSVGError) -> CGImage {
        let width = max(1, Int(pixelSize.width.isFinite ? pixelSize.width.rounded() : 1))
        let height = max(1, Int(pixelSize.height.isFinite ? pixelSize.height.rounded() : 1))
        guard CGFloat(width) * CGFloat(height) <= Self.maxPixels else { throw .tooLarge }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw .tooLarge
        }
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        // SVG user space has its origin at the top left.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        if let viewBox {
            context.concatenate(viewBox.transform(into: frame))
        } else if intrinsicSize.width > 0, intrinsicSize.height > 0 {
            context.scaleBy(x: frame.width / intrinsicSize.width, y: frame.height / intrinsicSize.height)
        }
        let viewport = viewBox?.rect.size ?? intrinsicSize
        try HSVGRenderer(context: context, elements: elements, styleSheet: styleSheet).renderRoot(root, viewport: viewport)

        guard let image = context.makeImage() else { throw .tooLarge }
        return image
    }
}

// MARK: - Size

extension HSVGDocument {
    /// The size of the document in points: absolute `width`/`height`, completed from the
    /// `viewBox` aspect ratio when only one is given, else the `viewBox` size, else 300x150.
    /// - Parameters:
    ///   - root: The root element.
    ///   - viewBox: The root view box.
    private static func intrinsicSize(of root: HSVGElement, viewBox: HSVGViewBox?) -> CGSize {
        func absolute(_ name: String) -> CGFloat? {
            guard let length = HSVGLength.parse(root.attributes[name]), !length.isPercentage, length.value > 0 else { return nil }
            return length.resolved(viewport: .zero, axis: .other)
        }
        let width = absolute("width")
        let height = absolute("height")
        let ratio = viewBox.map { $0.rect.width / $0.rect.height }
        switch (width, height) {
        case let (width?, height?):
            return CGSize(width: width, height: height)
        case let (width?, nil):
            return CGSize(width: width, height: ratio.map { width / $0 } ?? 150)
        case let (nil, height?):
            return CGSize(width: ratio.map { height * $0 } ?? 300, height: height)
        case (nil, nil):
            return viewBox?.rect.size ?? CGSize(width: 300, height: 150)
        }
    }
}
