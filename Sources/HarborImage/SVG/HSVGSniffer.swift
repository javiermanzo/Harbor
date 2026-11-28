//
//  HSVGSniffer.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// Detects SVG documents from their first bytes, without parsing them.
enum HSVGSniffer {
    /// Number of leading bytes inspected: the `<svg` root must start within them.
    static let sniffLength = 4096
}

// MARK: - Detection

extension HSVGSniffer {
    /// Whether `data` looks like an SVG document.
    ///
    /// After an optional UTF-8 byte order mark and whitespace, the data must start with
    /// `<?xml`, `<svg`, `<!--` or `<!DOCTYPE svg`, and the first element of the document (after
    /// the XML declaration, comments, processing instructions and a DOCTYPE) must be `<svg`
    /// within the first 4 KB. An HTML page that embeds an `<svg>` does not match, because its
    /// first element is `<html>` (or another HTML element).
    /// - Parameter data: The bytes to inspect.
    /// - Returns: `true` when the bytes look like an SVG document.
    static func isSVG(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(sniffLength))
        var index = 0
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            index = 3
        }
        index = skipWhitespace(bytes, from: index)
        let rest = bytes[index...]
        let validStart = rest.starts(with: Array("<?xml".utf8))
            || rest.starts(with: Array("<svg".utf8))
            || rest.starts(with: Array("<!--".utf8))
            || hasPrefix(bytes, at: index, "<!doctype svg", caseInsensitive: true)
        guard validStart else { return false }
        return firstElementIsSVG(bytes, from: index)
    }
}

// MARK: - Prolog Scanning

private extension HSVGSniffer {
    /// Skips the prolog (declarations, comments, processing instructions, DOCTYPE and
    /// whitespace) and checks that the next tag opens an `svg` element.
    /// - Parameters:
    ///   - bytes: The inspected bytes.
    ///   - start: The index where the prolog starts.
    /// - Returns: `true` when the first element is `<svg` (optionally namespace-prefixed as `<svg:svg`).
    static func firstElementIsSVG(_ bytes: [UInt8], from start: Int) -> Bool {
        var index = start
        while true {
            index = skipWhitespace(bytes, from: index)
            guard index < bytes.count, bytes[index] == UInt8(ascii: "<") else { return false }
            if hasPrefix(bytes, at: index, "<!--", caseInsensitive: false) {
                guard let end = find(bytes, "-->", from: index + 4) else { return false }
                index = end + 3
            } else if hasPrefix(bytes, at: index, "<?", caseInsensitive: false) {
                guard let end = find(bytes, "?>", from: index + 2) else { return false }
                index = end + 2
            } else if hasPrefix(bytes, at: index, "<!doctype", caseInsensitive: true) {
                guard let end = endOfDoctype(bytes, from: index + 9) else { return false }
                index = end + 1
            } else {
                return isSVGTag(bytes, at: index + 1)
            }
        }
    }

    /// Whether the bytes at `index` are `svg` or `svg:svg` followed by a tag delimiter.
    /// - Parameters:
    ///   - bytes: The inspected bytes.
    ///   - index: The index right after `<`.
    /// - Returns: `true` when the tag name is `svg`.
    static func isSVGTag(_ bytes: [UInt8], at index: Int) -> Bool {
        for name in ["svg", "svg:svg"] where hasPrefix(bytes, at: index, name, caseInsensitive: false) {
            let next = index + name.utf8.count
            guard next < bytes.count else { return false }
            let delimiter = bytes[next]
            if isWhitespace(delimiter) || delimiter == UInt8(ascii: ">") || delimiter == UInt8(ascii: "/") {
                return true
            }
        }
        return false
    }

    /// Finds the `>` that closes a DOCTYPE, skipping quoted strings and an internal subset.
    /// - Parameters:
    ///   - bytes: The inspected bytes.
    ///   - start: The index right after `<!DOCTYPE`.
    /// - Returns: The index of the closing `>`, or `nil` when it is not within the bytes.
    static func endOfDoctype(_ bytes: [UInt8], from start: Int) -> Int? {
        var index = start
        var quote: UInt8?
        var bracketDepth = 0
        while index < bytes.count {
            let byte = bytes[index]
            if let open = quote {
                if byte == open { quote = nil }
            } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                quote = byte
            } else if byte == UInt8(ascii: "[") {
                bracketDepth += 1
            } else if byte == UInt8(ascii: "]") {
                bracketDepth -= 1
            } else if byte == UInt8(ascii: ">"), bracketDepth <= 0 {
                return index
            }
            index += 1
        }
        return nil
    }

    /// Returns the first index after `start` that is not XML whitespace.
    /// - Parameters:
    ///   - bytes: The inspected bytes.
    ///   - start: The index to start from.
    /// - Returns: The index of the first non-whitespace byte, or `bytes.count`.
    static func skipWhitespace(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count, isWhitespace(bytes[index]) {
            index += 1
        }
        return index
    }

    /// Whether `byte` is XML whitespace (space, tab, line feed or carriage return).
    /// - Parameter byte: The byte to test.
    /// - Returns: `true` for whitespace.
    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    /// Whether `bytes` contains `prefix` at `index`.
    /// - Parameters:
    ///   - bytes: The inspected bytes.
    ///   - index: Where the prefix must start.
    ///   - prefix: The ASCII text to look for.
    ///   - caseInsensitive: Whether ASCII letters match regardless of case.
    /// - Returns: `true` when the prefix is present.
    static func hasPrefix(_ bytes: [UInt8], at index: Int, _ prefix: String, caseInsensitive: Bool) -> Bool {
        let expected = Array(prefix.utf8)
        guard index >= 0, index + expected.count <= bytes.count else { return false }
        for offset in 0..<expected.count {
            var actual = bytes[index + offset]
            var wanted = expected[offset]
            if caseInsensitive {
                actual = lowercased(actual)
                wanted = lowercased(wanted)
            }
            if actual != wanted { return false }
        }
        return true
    }

    /// Finds the first occurrence of `needle` at or after `start`.
    /// - Parameters:
    ///   - bytes: The inspected bytes.
    ///   - needle: The ASCII text to look for.
    ///   - start: The index to start from.
    /// - Returns: The index where `needle` starts, or `nil`.
    static func find(_ bytes: [UInt8], _ needle: String, from start: Int) -> Int? {
        let count = needle.utf8.count
        var index = start
        while index + count <= bytes.count {
            if hasPrefix(bytes, at: index, needle, caseInsensitive: false) { return index }
            index += 1
        }
        return nil
    }

    /// Lowercases an ASCII letter, leaving other bytes untouched.
    /// - Parameter byte: The byte to lowercase.
    /// - Returns: The lowercased byte.
    static func lowercased(_ byte: UInt8) -> UInt8 {
        (byte >= 0x41 && byte <= 0x5A) ? byte + 0x20 : byte
    }
}
