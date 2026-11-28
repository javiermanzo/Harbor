//
//  HImageColor.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// An sRGB color used by the processors (borders, tints, padding). A value type, so processors
/// stay `Sendable` and their identifiers stable.
public struct HImageColor: Sendable, Hashable {
    /// Red component in `0...1`.
    public let red: Double
    /// Green component in `0...1`.
    public let green: Double
    /// Blue component in `0...1`.
    public let blue: Double
    /// Opacity in `0...1`.
    public let alpha: Double

    /// Creates a color from sRGB components. Values are clamped to `0...1`.
    /// - Parameters:
    ///   - red: Red component.
    ///   - green: Green component.
    ///   - blue: Blue component.
    ///   - alpha: Opacity. Default: 1.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamped(red)
        self.green = Self.clamped(green)
        self.blue = Self.clamped(blue)
        self.alpha = Self.clamped(alpha)
    }

    /// Creates a color from a `CGColor`, converted to sRGB.
    /// - Parameter cgColor: The color.
    /// - Returns: `nil` when the color cannot be converted to sRGB (a pattern, for example).
    public init?(cgColor: CGColor) {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: sRGB, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 4 else {
            return nil
        }
        self.init(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]), alpha: Double(components[3]))
    }
}

// MARK: - Named Colors

public extension HImageColor {
    /// Opaque black.
    static let black = HImageColor(red: 0, green: 0, blue: 0)
    /// Opaque white.
    static let white = HImageColor(red: 1, green: 1, blue: 1)
    /// Fully transparent.
    static let clear = HImageColor(red: 0, green: 0, blue: 0, alpha: 0)
}

// MARK: - Core Graphics

extension HImageColor {
    /// The color as a `CGColor`.
    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// The identifier of the color in processor identifiers.
    var identifier: String {
        String(format: "#%.3f,%.3f,%.3f,%.3f", red, green, blue, alpha)
    }

    /// Clamps a component to `0...1`; a value that is not finite becomes 0.
    /// - Parameter value: The component.
    private static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}
