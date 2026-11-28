//
//  HSVGScanner.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// A cursor over the UTF-8 bytes of an attribute value that reads the SVG micro-syntaxes:
/// numbers in the compact SVG grammar (`1.5.5`, `-1-2`, `1e-3`), arc flags written without
/// separators, and comma-or-whitespace separators.
struct HSVGScanner {
    /// The bytes being scanned.
    let bytes: [UInt8]
    /// The index of the next unread byte.
    var index = 0

    /// Creates a scanner over a string.
    /// - Parameter text: The text to scan.
    init(_ text: String) {
        self.bytes = Array(text.utf8)
    }
}

// MARK: - State

extension HSVGScanner {
    /// Whether every byte has been read.
    var isAtEnd: Bool {
        index >= bytes.count
    }

    /// The next unread byte, or `nil` at the end.
    var peek: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }
}

// MARK: - Separators

extension HSVGScanner {
    /// Whether `byte` is whitespace in the SVG grammar (space, tab, line feed, form feed, carriage return).
    /// - Parameter byte: The byte to test.
    /// - Returns: `true` for whitespace.
    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D
    }

    /// Skips whitespace.
    mutating func skipWhitespace() {
        while let byte = peek, Self.isWhitespace(byte) {
            index += 1
        }
    }

    /// Skips whitespace, at most one comma, and the whitespace after it.
    mutating func skipCommaWhitespace() {
        skipWhitespace()
        if peek == UInt8(ascii: ",") {
            index += 1
            skipWhitespace()
        }
    }
}

// MARK: - Numbers

extension HSVGScanner {
    /// Whether `byte` is an ASCII digit.
    /// - Parameter byte: The byte to test.
    /// - Returns: `true` for `0`...`9`.
    static func isDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }

    /// Reads a number: an optional sign, digits with an optional fraction (or a fraction
    /// alone) and an optional exponent. The exponent is only read when digits follow the `e`,
    /// so `1em` reads `1` and leaves `em`.
    /// - Returns: The number, or `nil` (without consuming anything) when no number starts here.
    mutating func scanNumber() -> Double? {
        let start = index
        var cursor = index
        if cursor < bytes.count, bytes[cursor] == UInt8(ascii: "+") || bytes[cursor] == UInt8(ascii: "-") {
            cursor += 1
        }
        var digits = 0
        while cursor < bytes.count, Self.isDigit(bytes[cursor]) {
            cursor += 1
            digits += 1
        }
        if cursor < bytes.count, bytes[cursor] == UInt8(ascii: ".") {
            var fraction = 0
            var probe = cursor + 1
            while probe < bytes.count, Self.isDigit(bytes[probe]) {
                probe += 1
                fraction += 1
            }
            // `5.` is a valid number in the SVG grammar; a lone `.` is not.
            if fraction > 0 || digits > 0 {
                cursor = probe
                digits += fraction
            }
        }
        guard digits > 0 else { return nil }
        if cursor < bytes.count, bytes[cursor] == UInt8(ascii: "e") || bytes[cursor] == UInt8(ascii: "E") {
            var probe = cursor + 1
            if probe < bytes.count, bytes[probe] == UInt8(ascii: "+") || bytes[probe] == UInt8(ascii: "-") {
                probe += 1
            }
            if probe < bytes.count, Self.isDigit(bytes[probe]) {
                while probe < bytes.count, Self.isDigit(bytes[probe]) {
                    probe += 1
                }
                cursor = probe
            }
        }
        let text = String(bytes: bytes[start..<cursor], encoding: .ascii) ?? ""
        guard let value = Double(text), value.isFinite else { return nil }
        index = cursor
        return value
    }

    /// Reads an arc flag: a single `0` or `1`, which may be followed by the next number
    /// without a separator (`a1 1 0 0110 10`).
    /// - Returns: The flag, or `nil` (without consuming anything) when no flag starts here.
    mutating func scanFlag() -> Bool? {
        switch peek {
        case UInt8(ascii: "0"):
            index += 1
            return false
        case UInt8(ascii: "1"):
            index += 1
            return true
        default:
            return nil
        }
    }

    /// Reads a run of ASCII letters and `%`, used for units after a number.
    /// - Returns: The unit, lowercased, or an empty string when none follows.
    mutating func scanUnit() -> String {
        let start = index
        while let byte = peek, (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == UInt8(ascii: "%") {
            index += 1
        }
        return (String(bytes: bytes[start..<index], encoding: .ascii) ?? "").lowercased()
    }

    /// Reads a whitespace- or comma-separated list of numbers until the end.
    /// - Parameter text: The list to read.
    /// - Returns: The numbers, or `nil` when the text holds anything else.
    static func numberList(_ text: String) -> [Double]? {
        var scanner = HSVGScanner(text)
        var numbers: [Double] = []
        scanner.skipWhitespace()
        while !scanner.isAtEnd {
            guard let number = scanner.scanNumber() else { return nil }
            numbers.append(number)
            scanner.skipCommaWhitespace()
        }
        return numbers
    }
}
