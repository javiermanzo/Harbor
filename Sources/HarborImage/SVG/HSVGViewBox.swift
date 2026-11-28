//
//  HSVGViewBox.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// A `viewBox` and its `preserveAspectRatio`: how user coordinates map into a viewport.
struct HSVGViewBox: Sendable, Equatable {
    /// The `viewBox` rectangle in user units.
    let rect: CGRect
    /// The horizontal alignment: -1 min, 0 mid, 1 max; `nil` for `none` (non-uniform scaling).
    let alignX: Int?
    /// The vertical alignment: -1 min, 0 mid, 1 max.
    let alignY: Int
    /// Whether the content covers the viewport (`slice`) instead of fitting in it (`meet`).
    let isSlice: Bool
}

// MARK: - Parsing

extension HSVGViewBox {
    /// Parses the `viewBox` and `preserveAspectRatio` attributes of an element.
    /// - Parameter element: The element.
    /// - Returns: The view box, or `nil` without a valid `viewBox` (a non-positive size disables it).
    static func parse(_ element: HSVGElement) -> HSVGViewBox? {
        guard let text = element.attributes["viewBox"], let numbers = HSVGScanner.numberList(text), numbers.count == 4,
              numbers[2] > 0, numbers[3] > 0 else {
            return nil
        }
        let rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        let words = (element.attributes["preserveAspectRatio"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init).filter { $0 != "defer" }
        let align = words.first ?? "xMidYMid"
        let isSlice = words.dropFirst().first == "slice"
        guard align != "none" else {
            return HSVGViewBox(rect: rect, alignX: nil, alignY: 0, isSlice: false)
        }
        func position(_ text: Substring) -> Int {
            text == "Min" ? -1 : text == "Max" ? 1 : 0
        }
        let xPart = align.dropFirst(1).prefix(3)
        let yPart = align.dropFirst(5).prefix(3)
        return HSVGViewBox(rect: rect, alignX: position(xPart), alignY: position(yPart), isSlice: isSlice)
    }
}

// MARK: - Mapping

extension HSVGViewBox {
    /// The transform from the view box into the viewport.
    /// - Parameter viewport: The viewport rectangle.
    func transform(into viewport: CGRect) -> CGAffineTransform {
        var scaleX = viewport.width / rect.width
        var scaleY = viewport.height / rect.height
        guard let alignX else {
            return CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleY, tx: viewport.minX - rect.minX * scaleX, ty: viewport.minY - rect.minY * scaleY)
        }
        let scale = isSlice ? max(scaleX, scaleY) : min(scaleX, scaleY)
        scaleX = scale
        scaleY = scale
        var translateX = viewport.minX - rect.minX * scale
        var translateY = viewport.minY - rect.minY * scale
        let extraX = viewport.width - rect.width * scale
        let extraY = viewport.height - rect.height * scale
        translateX += alignX < 0 ? 0 : alignX == 0 ? extraX / 2 : extraX
        translateY += alignY < 0 ? 0 : alignY == 0 ? extraY / 2 : extraY
        return CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleY, tx: translateX, ty: translateY)
    }
}
