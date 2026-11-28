//
//  HSVGXMLReader.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// Reads SVG bytes into an `HSVGElement` tree with `XMLParser`, refusing what is unsafe before
/// it is processed: external entities are never resolved; external, parameter and unparsed
/// entities, entities that reference others (expansion bombs), more than 32 declarations and
/// values over 4,096 characters are rejected, and so are scripts and event attributes. Elements of other namespaces (`sodipodi:`, `inkscape:`, ...)
/// are dropped with their children.
final class HSVGXMLReader: NSObject {
    /// Most elements accepted in a document.
    static let maxElements = 200_000
    /// Deepest nesting accepted.
    static let maxDepth = 256
    /// Most entity declarations accepted (simple text entities, as exported by Illustrator).
    private static let maxEntities = 32

    /// An element being built.
    private final class Builder {
        /// The element name.
        let name: String
        /// The attributes.
        let attributes: [String: String]
        /// The finished children.
        var children: [HSVGElement] = []
        /// The text collected so far (only for `<style>`).
        var text = ""
        /// Whether the element (and its subtree) is dropped.
        let isIgnored: Bool

        /// Creates a builder.
        /// - Parameters:
        ///   - name: The element name.
        ///   - attributes: The attributes.
        ///   - isIgnored: Whether the element is dropped.
        init(name: String, attributes: [String: String], isIgnored: Bool) {
            self.name = name
            self.attributes = attributes
            self.isIgnored = isIgnored
        }
    }

    /// The open elements.
    private var stack: [Builder] = []
    /// The root, once closed.
    private var root: HSVGElement?
    /// Elements read so far.
    private var elementCount = 0
    /// Entity declarations read so far.
    private var entityCount = 0
    /// The first error found; parsing stops at it.
    private var failure: HSVGError?

    /// Creates a reader.
    private override init() {}
}

// MARK: - Reading

extension HSVGXMLReader {
    /// Parses the bytes.
    /// - Parameter data: The SVG bytes.
    /// - Returns: The root element, which is `<svg>`.
    /// - Throws: `.unsafe`, `.tooLarge`, or `.malformed` for XML errors and another root.
    static func read(_ data: Data) throws(HSVGError) -> HSVGElement {
        try checkEntityDeclarations(data)
        let reader = HSVGXMLReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.delegate = reader
        let succeeded = parser.parse()
        if let failure = reader.failure { throw failure }
        guard succeeded else {
            throw .malformed(parser.parserError.map { "XML error \(($0 as NSError).code) at line \(parser.lineNumber)" } ?? "Not well-formed XML")
        }
        guard let root = reader.root, root.name == "svg" else {
            throw .malformed("The root element is not <svg>")
        }
        return root
    }

    /// Rejects entity declarations that `XMLParser` does not report reliably: external
    /// (`SYSTEM`, `PUBLIC`) and parameter (`%`) entities, and entities that reference others.
    /// The whole document is scanned, so a declaration cannot hide after a comment or padding;
    /// the text `<!ENTITY` inside a comment or a `<style>` is checked too, which can only reject
    /// a document, never accept an unsafe one.
    /// - Parameter data: The SVG bytes.
    private static func checkEntityDeclarations(_ data: Data) throws(HSVGError) {
        let marker = Data("<!ENTITY".utf8)
        var searchStart = data.startIndex
        while let range = data.range(of: marker, in: searchStart..<data.endIndex) {
            let declarationEnd = data[range.upperBound...].firstIndex(of: UInt8(ascii: ">")) ?? data.endIndex
            let declaration = String(bytes: data[range.upperBound..<declarationEnd], encoding: .utf8) ?? "%"
            let upper = declaration.uppercased()
            if upper.contains("SYSTEM") || upper.contains("PUBLIC") || declaration.contains("%") || declaration.contains("&") {
                throw .unsafe("entity declaration")
            }
            searchStart = range.upperBound
        }
    }

    /// Records the first error and stops the parser.
    /// - Parameters:
    ///   - error: The error.
    ///   - parser: The parser.
    private func fail(_ error: HSVGError, _ parser: XMLParser) {
        if failure == nil { failure = error }
        parser.abortParsing()
    }
}

// MARK: - XMLParserDelegate

extension HSVGXMLReader: XMLParserDelegate {
    /// Opens an element.
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        elementCount += 1
        guard elementCount <= Self.maxElements, stack.count < Self.maxDepth else {
            fail(.tooLarge, parser)
            return
        }

        var name = elementName
        var isIgnored = stack.last?.isIgnored ?? false
        if name.hasPrefix("svg:") {
            name.removeFirst(4)
        } else if name.contains(":") {
            isIgnored = true
        }
        if !isIgnored {
            if name == "script" || name == "handler" {
                fail(.unsafe("<\(name)>"), parser)
                return
            }
            if let event = attributeDict.keys.first(where: { $0.lowercased().hasPrefix("on") }) {
                fail(.unsafe("event attribute \(event)"), parser)
                return
            }
        }
        stack.append(Builder(name: name, attributes: attributeDict, isIgnored: isIgnored))
    }

    /// Closes an element.
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let builder = stack.popLast() else { return }
        guard !builder.isIgnored else { return }
        let element = HSVGElement(name: builder.name, attributes: builder.attributes, children: builder.children, text: builder.text)
        if let parent = stack.last {
            if !parent.isIgnored { parent.children.append(element) }
        } else {
            root = element
        }
    }

    /// Collects text, kept for `<style>` only.
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if let current = stack.last, current.name == "style", !current.isIgnored {
            current.text += string
        }
    }

    /// Collects CDATA, kept for `<style>` only.
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let current = stack.last, current.name == "style", !current.isIgnored {
            current.text += String(bytes: CDATABlock, encoding: .utf8) ?? ""
        }
    }

    /// Accepts simple text entities; rejects nested references (expansion bombs), values over
    /// 4,096 characters and more than 32 declarations.
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        entityCount += 1
        if entityCount > Self.maxEntities || (value ?? "").contains("&") || (value ?? "").count > 4096 {
            fail(.unsafe("entity declaration \(name)"), parser)
        }
    }

    /// Rejects entities that point outside the document.
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
        fail(.unsafe("external entity \(name)"), parser)
    }

    /// Rejects unparsed entities.
    func parser(_ parser: XMLParser, foundUnparsedEntityDeclarationWithName name: String, publicID: String?, systemID: String?, notationName: String?) {
        fail(.unsafe("unparsed entity \(name)"), parser)
    }

    /// Never resolves an external entity.
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        fail(.unsafe("external entity \(name)"), parser)
        return nil
    }

    /// Does nothing: the parser stops on its own and `read(_:)` reports `parserError`.
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {}
}
