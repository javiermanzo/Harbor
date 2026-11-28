//
//  HSVGPathParser.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// Parses the path data grammar of the `d` attribute (`M L H V C S Q T A Z`, absolute and
/// relative, implicit repeated commands, compact numbers and unseparated arc flags).
///
/// Following the SVG error-handling rules, a path with an error renders up to the last
/// complete segment before it: `M 0 0 L 10 10 L 5` draws the first line only.
struct HSVGPathParser {
    /// The cursor over the path data.
    private var scanner: HSVGScanner
    /// The path built so far.
    private var path = HSVGPath()
    /// The current point.
    private var current = CGPoint.zero
    /// The start of the current subpath, where `Z` returns to.
    private var subpathStart = CGPoint.zero
    /// The last control point of the previous segment when it was a cubic (`C`/`S`), used
    /// to reflect the first control point of `S`.
    private var lastCubicControl: CGPoint?
    /// The control point of the previous segment when it was a quadratic (`Q`/`T`), used
    /// to reflect the control point of `T`.
    private var lastQuadControl: CGPoint?

    /// Creates a parser.
    /// - Parameter data: The path data.
    private init(_ data: String) {
        self.scanner = HSVGScanner(data)
    }
}

// MARK: - Parsing

extension HSVGPathParser {
    /// Parses path data into a path.
    /// - Parameter data: The value of a `d` attribute.
    /// - Returns: The path, up to the first error.
    static func parse(_ data: String) -> HSVGPath {
        var parser = HSVGPathParser(data)
        parser.run()
        return parser.path
    }

    /// Reads every command until the end or the first error.
    private mutating func run() {
        scanner.skipWhitespace()
        var command: UInt8?
        var isFirstCommand = true
        while !scanner.isAtEnd {
            if let byte = scanner.peek, Self.isCommand(byte) {
                scanner.index += 1
                command = byte
            } else if command == nil || command == UInt8(ascii: "z") || command == UInt8(ascii: "Z") {
                // Numbers without a command, or numbers after `Z`, are an error.
                return
            }
            guard let active = command else { return }
            // The first command must be a moveto.
            if isFirstCommand, active != UInt8(ascii: "M"), active != UInt8(ascii: "m") { return }
            isFirstCommand = false
            scanner.skipWhitespace()
            guard readSegment(active) else { return }
            scanner.skipCommaWhitespace()
            // After a moveto, repeated coordinate pairs are implicit linetos.
            if active == UInt8(ascii: "M") {
                command = UInt8(ascii: "L")
            } else if active == UInt8(ascii: "m") {
                command = UInt8(ascii: "l")
            }
        }
    }

    /// Whether `byte` is one of the twenty path command letters.
    /// - Parameter byte: The byte to test.
    /// - Returns: `true` for a command letter.
    private static func isCommand(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "M"), UInt8(ascii: "m"), UInt8(ascii: "L"), UInt8(ascii: "l"),
             UInt8(ascii: "H"), UInt8(ascii: "h"), UInt8(ascii: "V"), UInt8(ascii: "v"),
             UInt8(ascii: "C"), UInt8(ascii: "c"), UInt8(ascii: "S"), UInt8(ascii: "s"),
             UInt8(ascii: "Q"), UInt8(ascii: "q"), UInt8(ascii: "T"), UInt8(ascii: "t"),
             UInt8(ascii: "A"), UInt8(ascii: "a"), UInt8(ascii: "Z"), UInt8(ascii: "z"):
            return true
        default:
            return false
        }
    }

    /// Reads the arguments of one segment and appends it.
    /// - Parameter command: The command letter.
    /// - Returns: `false` when the arguments are missing or invalid.
    private mutating func readSegment(_ command: UInt8) -> Bool {
        let relative = command >= UInt8(ascii: "a")
        let origin = relative ? current : .zero
        switch command | 0x20 {
        case UInt8(ascii: "m"):
            guard let point = readPoint(origin) else { return false }
            path.move(to: point)
            current = point
            subpathStart = point
            clearControls()
        case UInt8(ascii: "l"):
            guard let point = readPoint(origin) else { return false }
            lineTo(point)
        case UInt8(ascii: "h"):
            guard let x = scanner.scanNumber() else { return false }
            lineTo(CGPoint(x: x + (relative ? current.x : 0), y: current.y))
        case UInt8(ascii: "v"):
            guard let y = scanner.scanNumber() else { return false }
            lineTo(CGPoint(x: current.x, y: y + (relative ? current.y : 0)))
        case UInt8(ascii: "c"):
            return readCubic(origin: origin, smooth: false)
        case UInt8(ascii: "s"):
            return readCubic(origin: origin, smooth: true)
        case UInt8(ascii: "q"):
            return readQuad(origin: origin, smooth: false)
        case UInt8(ascii: "t"):
            return readQuad(origin: origin, smooth: true)
        case UInt8(ascii: "a"):
            return readArc(origin: origin)
        default:
            path.close()
            current = subpathStart
            clearControls()
        }
        return true
    }

    /// Reads `x y`, offset by `origin`.
    /// - Parameter origin: The current point for relative commands, `.zero` otherwise.
    /// - Returns: The point, or `nil` when the pair is incomplete.
    private mutating func readPoint(_ origin: CGPoint) -> CGPoint? {
        guard let x = scanner.scanNumber() else { return nil }
        scanner.skipCommaWhitespace()
        guard let y = scanner.scanNumber() else { return nil }
        return CGPoint(x: x + origin.x, y: y + origin.y)
    }

    /// Reads a point that follows a separator.
    /// - Parameter origin: The current point for relative commands, `.zero` otherwise.
    /// - Returns: The point, or `nil` when the pair is incomplete.
    private mutating func readNextPoint(_ origin: CGPoint) -> CGPoint? {
        scanner.skipCommaWhitespace()
        return readPoint(origin)
    }

    /// Appends a line and makes its end the current point.
    /// - Parameter point: The end of the line.
    private mutating func lineTo(_ point: CGPoint) {
        path.line(to: point)
        current = point
        clearControls()
    }

    /// Forgets the control points used by `S` and `T` reflection.
    private mutating func clearControls() {
        lastCubicControl = nil
        lastQuadControl = nil
    }

    /// Reads a `C` or `S` segment.
    /// - Parameters:
    ///   - origin: The current point for relative commands, `.zero` otherwise.
    ///   - smooth: Whether the first control point is the reflection of the previous one (`S`).
    /// - Returns: `false` when the arguments are incomplete.
    private mutating func readCubic(origin: CGPoint, smooth: Bool) -> Bool {
        let control1: CGPoint
        if smooth {
            control1 = lastCubicControl.map { reflect($0) } ?? current
        } else {
            guard let point = readPoint(origin) else { return false }
            control1 = point
        }
        guard let control2 = smooth ? readPoint(origin) : readNextPoint(origin),
              let end = readNextPoint(origin) else { return false }
        path.cubic(to: end, control1: control1, control2: control2)
        current = end
        lastCubicControl = control2
        lastQuadControl = nil
        return true
    }

    /// Reads a `Q` or `T` segment.
    /// - Parameters:
    ///   - origin: The current point for relative commands, `.zero` otherwise.
    ///   - smooth: Whether the control point is the reflection of the previous one (`T`).
    /// - Returns: `false` when the arguments are incomplete.
    private mutating func readQuad(origin: CGPoint, smooth: Bool) -> Bool {
        let control: CGPoint
        if smooth {
            control = lastQuadControl.map { reflect($0) } ?? current
        } else {
            guard let point = readPoint(origin) else { return false }
            control = point
        }
        guard let end = smooth ? readPoint(origin) : readNextPoint(origin) else { return false }
        path.segments.append(.quad(control: control, to: end))
        current = end
        lastQuadControl = control
        lastCubicControl = nil
        return true
    }

    /// Reads an `A` segment and appends it as cubic curves.
    /// - Parameter origin: The current point for relative commands, `.zero` otherwise.
    /// - Returns: `false` when the arguments are incomplete.
    private mutating func readArc(origin: CGPoint) -> Bool {
        guard let rx = scanner.scanNumber() else { return false }
        scanner.skipCommaWhitespace()
        guard let ry = scanner.scanNumber() else { return false }
        scanner.skipCommaWhitespace()
        guard let rotation = scanner.scanNumber() else { return false }
        scanner.skipCommaWhitespace()
        guard let largeArc = scanner.scanFlag() else { return false }
        scanner.skipCommaWhitespace()
        guard let sweep = scanner.scanFlag() else { return false }
        guard let end = readNextPoint(origin) else { return false }
        let arc = HSVGArc(start: current, end: end, radii: CGSize(width: rx, height: ry),
                          rotation: rotation, largeArc: largeArc, sweep: sweep)
        arc.append(to: &path)
        current = end
        clearControls()
        return true
    }

    /// Reflects `point` about the current point.
    /// - Parameter point: The control point to reflect.
    /// - Returns: The reflected point.
    private func reflect(_ point: CGPoint) -> CGPoint {
        CGPoint(x: 2 * current.x - point.x, y: 2 * current.y - point.y)
    }
}
