//
//  HSVGStyleSheet.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// The CSS of an SVG document: `<style>` elements with simple selectors (type, class, id, `*`,
/// and a type combined with a class or an id, in comma lists). Combinators, attribute selectors
/// and pseudo-classes throw `.unsupported`; `@import` throws `.unsafe`; other at-rules except
/// `@charset` throw `.unsupported`.
struct HSVGStyleSheet: Sendable {
    /// A simple selector.
    struct Selector: Sendable {
        /// The element name, or `nil` for any.
        let type: String?
        /// The class, if any.
        let className: String?
        /// The id, if any.
        let id: String?

        /// The CSS specificity: ids, then classes, then types.
        var specificity: Int {
            (id == nil ? 0 : 10_000) + (className == nil ? 0 : 100) + (type == nil ? 0 : 1)
        }

        /// Whether the selector matches the element.
        /// - Parameter element: The element.
        func matches(_ element: HSVGElement) -> Bool {
            if let type, type != element.name { return false }
            if let id, id != element.id { return false }
            if let className, !element.classes.contains(className) { return false }
            return true
        }
    }

    /// A rule: a selector and its declarations.
    struct Rule: Sendable {
        /// The selector.
        let selector: Selector
        /// The declarations, in order.
        let declarations: [Declaration]
        /// The position of the rule in the document, for ties.
        let order: Int
    }

    /// A `property: value` pair.
    struct Declaration: Sendable {
        /// The property, lowercased.
        let property: String
        /// The value.
        let value: String
        /// Whether it is `!important`.
        let isImportant: Bool
    }

    /// The rules, sorted by specificity, then document order.
    let rules: [Rule]
}

// MARK: - Parsing

extension HSVGStyleSheet {
    /// Parses every `<style>` element of the document.
    /// - Parameter root: The root element.
    static func parse(root: HSVGElement) throws(HSVGError) -> HSVGStyleSheet {
        var styles: [HSVGElement] = []
        root.forEach { element in
            if element.name == "style" { styles.append(element) }
        }
        var rules: [Rule] = []
        for style in styles {
            rules += try parseRules(style.text, startingAt: rules.count)
        }
        return HSVGStyleSheet(rules: rules.sorted { ($0.selector.specificity, $0.order) < ($1.selector.specificity, $1.order) })
    }

    /// Parses the rules of one style sheet.
    /// - Parameters:
    ///   - css: The style sheet.
    ///   - start: The order of its first rule.
    private static func parseRules(_ css: String, startingAt start: Int) throws(HSVGError) -> [Rule] {
        var text = stripComments(css)
        // `@charset "UTF-8";` changes nothing for an SVG already decoded.
        while let range = text.range(of: "@charset") {
            let end = text[range.upperBound...].firstIndex(of: ";").map { text.index(after: $0) } ?? text.endIndex
            text.removeSubrange(range.lowerBound..<end)
        }
        if text.contains("@import") { throw .unsafe("@import") }
        if let atRule = text.range(of: "@") {
            throw .unsupported("CSS at-rule \(text[atRule.lowerBound...].prefix(while: { !$0.isWhitespace && $0 != "{" }))")
        }

        var rules: [Rule] = []
        var remainder = Substring(text)
        while let open = remainder.firstIndex(of: "{") {
            guard let close = remainder[open...].firstIndex(of: "}") else { throw .malformed("CSS block") }
            let selectorText = remainder[..<open]
            let declarations = parseDeclarations(String(remainder[remainder.index(after: open)..<close]))
            for part in selectorText.split(separator: ",") {
                let selector = try parseSelector(part.trimmingCharacters(in: .whitespacesAndNewlines))
                rules.append(Rule(selector: selector, declarations: declarations, order: start + rules.count))
            }
            remainder = remainder[remainder.index(after: close)...]
        }
        return rules
    }

    /// Parses a simple selector.
    /// - Parameter text: The selector.
    private static func parseSelector(_ text: String) throws(HSVGError) -> Selector {
        guard !text.isEmpty else { throw .malformed("empty CSS selector") }
        let forbidden: Set<Character> = [" ", ">", "+", "~", "[", ":", "\t", "\n"]
        if text.contains(where: { forbidden.contains($0) }) {
            throw .unsupported("CSS selector \"\(text)\"")
        }
        var type: String?
        var className: String?
        var id: String?
        var current = ""
        var kind: Character = "t"
        func flush() throws(HSVGError) {
            guard !current.isEmpty || kind == "t" else { throw .unsupported("CSS selector \"\(text)\"") }
            switch kind {
            case ".":
                guard className == nil else { throw .unsupported("CSS selector \"\(text)\"") }
                className = current
            case "#":
                guard id == nil else { throw .unsupported("CSS selector \"\(text)\"") }
                id = current
            default:
                if !current.isEmpty, current != "*" { type = current }
            }
            current = ""
        }
        for character in text {
            if character == "." || character == "#" {
                try flush()
                kind = character
            } else {
                current.append(character)
            }
        }
        try flush()
        return Selector(type: type, className: className, id: id)
    }

    /// Parses a declaration block or a `style` attribute.
    /// - Parameter text: The declarations.
    static func parseDeclarations(_ text: String) -> [Declaration] {
        stripComments(text).split(separator: ";").compactMap { part in
            guard let colon = part.firstIndex(of: ":") else { return nil }
            let property = part[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = part[part.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            var isImportant = false
            if let range = value.range(of: "!important", options: .caseInsensitive) {
                isImportant = true
                value = value[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !property.isEmpty, !value.isEmpty else { return nil }
            return Declaration(property: property, value: value, isImportant: isImportant)
        }
    }

    /// Removes `/* ... */` comments.
    /// - Parameter text: The CSS.
    private static func stripComments(_ text: String) -> String {
        var result = ""
        var remainder = Substring(text)
        while let start = remainder.range(of: "/*") {
            result += remainder[..<start.lowerBound]
            guard let end = remainder[start.upperBound...].range(of: "*/") else { return result }
            remainder = remainder[end.upperBound...]
        }
        return result + remainder
    }
}

// MARK: - Cascade

extension HSVGStyleSheet {
    /// The specified properties of an element: presentation attributes, then the style sheet
    /// rules by specificity, then the `style` attribute, then `!important` declarations.
    /// - Parameter element: The element.
    func declaredProperties(of element: HSVGElement) -> [String: String] {
        var properties: [String: String] = [:]
        for name in HSVGStyleSheet.presentationAttributes {
            if let value = element.attributes[name] { properties[name] = value }
        }
        var important: [Declaration] = []
        for rule in rules where rule.selector.matches(element) {
            for declaration in rule.declarations {
                if declaration.isImportant { important.append(declaration) } else { properties[declaration.property] = declaration.value }
            }
        }
        for declaration in HSVGStyleSheet.parseDeclarations(element.attributes["style"] ?? "") {
            if declaration.isImportant { important.append(declaration) } else { properties[declaration.property] = declaration.value }
        }
        for declaration in important {
            properties[declaration.property] = declaration.value
        }
        return properties
    }

    /// The presentation attributes read from elements.
    static let presentationAttributes: [String] = [
        "fill", "fill-opacity", "fill-rule", "stroke", "stroke-opacity", "stroke-width", "stroke-linecap",
        "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray", "stroke-dashoffset", "opacity", "color",
        "display", "visibility", "clip-path", "clip-rule", "stop-color", "stop-opacity", "filter", "mask",
        "marker", "marker-start", "marker-mid", "marker-end", "overflow", "paint-order", "vector-effect", "transform-origin",
    ]
}
