//
//  HSVGTransform.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// Parses the `transform` and `gradientTransform` attribute grammar (also used by `clipPath`):
/// `matrix`, `translate`, `scale`, `rotate` (with an optional center), `skewX` and `skewY`, in
/// lists separated by whitespace or commas.
enum HSVGTransform {
    /// Parses a transform list.
    /// - Parameter text: The attribute value.
    /// - Returns: The combined transform (the first function is the outermost).
    /// - Throws: `.malformed` for an invalid list.
    static func parse(_ text: String?) throws(HSVGError) -> CGAffineTransform {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .identity }
        var result = CGAffineTransform.identity
        var remainder = Substring(text)
        while true {
            remainder = remainder.drop(while: { $0.isWhitespace || $0 == "," })
            guard !remainder.isEmpty else { break }
            guard let open = remainder.firstIndex(of: "("), let close = remainder.firstIndex(of: ")"), open < close else {
                throw .malformed("transform \"\(text)\"")
            }
            let name = remainder[..<open].trimmingCharacters(in: .whitespaces)
            guard let arguments = HSVGScanner.numberList(String(remainder[remainder.index(after: open)..<close])) else {
                throw .malformed("transform \"\(text)\"")
            }
            // Each function applies inside the previous ones: result = function × result.
            result = try function(name, arguments, text: text).concatenating(result)
            remainder = remainder[remainder.index(after: close)...]
        }
        return result
    }

    /// Builds one transform function.
    /// - Parameters:
    ///   - name: The function name.
    ///   - arguments: Its numbers.
    ///   - text: The whole attribute, for errors.
    private static func function(_ name: String, _ arguments: [Double], text: String) throws(HSVGError) -> CGAffineTransform {
        let args = arguments.map { CGFloat($0) }
        switch (name, args.count) {
        case ("matrix", 6):
            return CGAffineTransform(a: args[0], b: args[1], c: args[2], d: args[3], tx: args[4], ty: args[5])
        case ("translate", 1):
            return CGAffineTransform(translationX: args[0], y: 0)
        case ("translate", 2):
            return CGAffineTransform(translationX: args[0], y: args[1])
        case ("scale", 1):
            return CGAffineTransform(scaleX: args[0], y: args[0])
        case ("scale", 2):
            return CGAffineTransform(scaleX: args[0], y: args[1])
        case ("rotate", 1):
            return CGAffineTransform(rotationAngle: args[0] * .pi / 180)
        case ("rotate", 3):
            return CGAffineTransform(translationX: -args[1], y: -args[2])
                .concatenating(CGAffineTransform(rotationAngle: args[0] * .pi / 180))
                .concatenating(CGAffineTransform(translationX: args[1], y: args[2]))
        case ("skewX", 1):
            return CGAffineTransform(a: 1, b: 0, c: tan(args[0] * .pi / 180), d: 1, tx: 0, ty: 0)
        case ("skewY", 1):
            return CGAffineTransform(a: 1, b: tan(args[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
        default:
            throw .malformed("transform \"\(text)\"")
        }
    }
}
