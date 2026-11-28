//
//  HSVGElement.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// An element of a parsed SVG document: immutable, so a document is parsed once and rendered
/// at many sizes from any thread.
final class HSVGElement: Sendable {
    /// The element name without the `svg:` prefix (`rect`, `linearGradient`, ...).
    let name: String
    /// The attributes, by their name as written (`xlink:href` keeps its prefix).
    let attributes: [String: String]
    /// The child elements, in document order.
    let children: [HSVGElement]
    /// The text content (only kept for `<style>`).
    let text: String

    /// Creates an element.
    /// - Parameters:
    ///   - name: The element name.
    ///   - attributes: The attributes.
    ///   - children: The child elements.
    ///   - text: The text content.
    init(name: String, attributes: [String: String], children: [HSVGElement], text: String) {
        self.name = name
        self.attributes = attributes
        self.children = children
        self.text = text
    }
}

// MARK: - Attributes

extension HSVGElement {
    /// The `id` attribute.
    var id: String? {
        attributes["id"]
    }

    /// The classes of the `class` attribute.
    var classes: [String] {
        (attributes["class"] ?? "").split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
    }

    /// The `href` or `xlink:href` attribute.
    var href: String? {
        (attributes["href"] ?? attributes["xlink:href"])?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Visits the element and its descendants, depth first.
    /// - Parameter body: Called for every element.
    func forEach(_ body: (HSVGElement) throws -> Void) rethrows {
        try body(self)
        for child in children {
            try child.forEach(body)
        }
    }
}
