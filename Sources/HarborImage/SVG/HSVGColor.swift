//
//  HSVGColor.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation

/// An sRGB color of an SVG document, with components in `0...1`.
struct HSVGColor: Sendable, Equatable {
    /// Red component.
    var red: Double
    /// Green component.
    var green: Double
    /// Blue component.
    var blue: Double
    /// Opacity.
    var alpha: Double

    /// Opaque black, the initial `fill` and `color`.
    static let black = HSVGColor(red: 0, green: 0, blue: 0, alpha: 1)
}

// MARK: - Parsing

extension HSVGColor {
    /// Parses a CSS color: `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()`, `hsl()`,
    /// `hsla()` (comma or space syntax, numbers or percentages), `transparent` and the CSS keywords.
    /// - Parameter text: The color text.
    /// - Returns: The color, or `nil` when the text is not a color.
    static func parse(_ text: String) -> HSVGColor? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("#") {
            return hex(String(value.dropFirst()))
        }
        if value == "transparent" {
            return HSVGColor(red: 0, green: 0, blue: 0, alpha: 0)
        }
        if let open = value.firstIndex(of: "("), value.hasSuffix(")") {
            let function = String(value[..<open]).trimmingCharacters(in: .whitespaces)
            let arguments = String(value[value.index(after: open)..<value.index(before: value.endIndex)])
            return functional(function, arguments)
        }
        guard let rgb = namedColors[value] else { return nil }
        return HSVGColor(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255, alpha: 1)
    }

    /// The color as a `CGColor`, with an extra opacity applied.
    /// - Parameter opacity: Multiplies the color's alpha.
    func cgColor(opacity: Double = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha * opacity)
    }

    /// Parses the hexadecimal forms.
    /// - Parameter digits: The digits after `#`.
    private static func hex(_ digits: String) -> HSVGColor? {
        guard [3, 4, 6, 8].contains(digits.count), let value = UInt64(digits, radix: 16) else { return nil }
        let expanded: UInt64
        let hasAlpha = digits.count == 4 || digits.count == 8
        if digits.count <= 4 {
            var result: UInt64 = 0
            for shift in stride(from: (digits.count - 1) * 4, through: 0, by: -4) {
                let nibble = value >> UInt64(shift) & 0xF
                result = result << 8 | nibble << 4 | nibble
            }
            expanded = result
        } else {
            expanded = value
        }
        let alpha = hasAlpha ? Double(expanded & 0xFF) / 255 : 1
        let rgb = hasAlpha ? expanded >> 8 : expanded
        return HSVGColor(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255, alpha: alpha)
    }

    /// Parses `rgb()`, `rgba()`, `hsl()` and `hsla()`.
    /// - Parameters:
    ///   - function: The function name.
    ///   - arguments: The text between the parentheses.
    private static func functional(_ function: String, _ arguments: String) -> HSVGColor? {
        let parts = arguments.replacingOccurrences(of: "/", with: " ")
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" || $0 == "\n" })
            .map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }
        let alpha = parts.count == 4 ? component(parts[3], scale: 1) : 1
        switch function {
        case "rgb", "rgba":
            guard let red = component(parts[0], scale: 255), let green = component(parts[1], scale: 255),
                  let blue = component(parts[2], scale: 255), let alpha else { return nil }
            return HSVGColor(red: clamp(red), green: clamp(green), blue: clamp(blue), alpha: clamp(alpha))
        case "hsl", "hsla":
            guard let hue = Double(parts[0].replacingOccurrences(of: "deg", with: "")),
                  let saturation = component(parts[1], scale: 100), let lightness = component(parts[2], scale: 100),
                  let alpha else { return nil }
            return fromHSL(hue: hue, saturation: clamp(saturation), lightness: clamp(lightness), alpha: clamp(alpha))
        default:
            return nil
        }
    }

    /// Reads a component as a fraction: a percentage, or a number divided by `scale`.
    /// - Parameters:
    ///   - text: The component.
    ///   - scale: The value of a full component as a number.
    private static func component(_ text: String, scale: Double) -> Double? {
        if text.hasSuffix("%") {
            return Double(text.dropLast()).map { $0 / 100 }
        }
        return Double(text).map { $0 / scale }
    }

    /// Converts HSL to RGB.
    /// - Parameters:
    ///   - hue: The hue in degrees.
    ///   - saturation: The saturation in `0...1`.
    ///   - lightness: The lightness in `0...1`.
    ///   - alpha: The opacity.
    private static func fromHSL(hue: Double, saturation: Double, lightness: Double, alpha: Double) -> HSVGColor {
        let normalizedHue = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        let upper = lightness <= 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let lower = 2 * lightness - upper
        func channel(_ offset: Double) -> Double {
            var value = normalizedHue + offset
            if value < 0 { value += 1 }
            if value > 1 { value -= 1 }
            if value < 1 / 6 { return lower + (upper - lower) * 6 * value }
            if value < 1 / 2 { return upper }
            if value < 2 / 3 { return lower + (upper - lower) * (2 / 3 - value) * 6 }
            return lower
        }
        return HSVGColor(red: clamp(channel(1 / 3)), green: clamp(channel(0)), blue: clamp(channel(-1 / 3)), alpha: alpha)
    }

    /// Clamps a component to `0...1`.
    /// - Parameter value: The component.
    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

// MARK: - Named Colors

extension HSVGColor {
    /// The CSS color keywords, as `0xRRGGBB`.
    private static let namedColors: [String: UInt32] = [
        "aliceblue": 0xF0F8FF, "antiquewhite": 0xFAEBD7, "aqua": 0x00FFFF, "aquamarine": 0x7FFFD4,
        "azure": 0xF0FFFF, "beige": 0xF5F5DC, "bisque": 0xFFE4C4, "black": 0x000000,
        "blanchedalmond": 0xFFEBCD, "blue": 0x0000FF, "blueviolet": 0x8A2BE2, "brown": 0xA52A2A,
        "burlywood": 0xDEB887, "cadetblue": 0x5F9EA0, "chartreuse": 0x7FFF00, "chocolate": 0xD2691E,
        "coral": 0xFF7F50, "cornflowerblue": 0x6495ED, "cornsilk": 0xFFF8DC, "crimson": 0xDC143C,
        "cyan": 0x00FFFF, "darkblue": 0x00008B, "darkcyan": 0x008B8B, "darkgoldenrod": 0xB8860B,
        "darkgray": 0xA9A9A9, "darkgreen": 0x006400, "darkgrey": 0xA9A9A9, "darkkhaki": 0xBDB76B,
        "darkmagenta": 0x8B008B, "darkolivegreen": 0x556B2F, "darkorange": 0xFF8C00, "darkorchid": 0x9932CC,
        "darkred": 0x8B0000, "darksalmon": 0xE9967A, "darkseagreen": 0x8FBC8F, "darkslateblue": 0x483D8B,
        "darkslategray": 0x2F4F4F, "darkslategrey": 0x2F4F4F, "darkturquoise": 0x00CED1, "darkviolet": 0x9400D3,
        "deeppink": 0xFF1493, "deepskyblue": 0x00BFFF, "dimgray": 0x696969, "dimgrey": 0x696969,
        "dodgerblue": 0x1E90FF, "firebrick": 0xB22222, "floralwhite": 0xFFFAF0, "forestgreen": 0x228B22,
        "fuchsia": 0xFF00FF, "gainsboro": 0xDCDCDC, "ghostwhite": 0xF8F8FF, "gold": 0xFFD700,
        "goldenrod": 0xDAA520, "gray": 0x808080, "green": 0x008000, "greenyellow": 0xADFF2F,
        "grey": 0x808080, "honeydew": 0xF0FFF0, "hotpink": 0xFF69B4, "indianred": 0xCD5C5C,
        "indigo": 0x4B0082, "ivory": 0xFFFFF0, "khaki": 0xF0E68C, "lavender": 0xE6E6FA,
        "lavenderblush": 0xFFF0F5, "lawngreen": 0x7CFC00, "lemonchiffon": 0xFFFACD, "lightblue": 0xADD8E6,
        "lightcoral": 0xF08080, "lightcyan": 0xE0FFFF, "lightgoldenrodyellow": 0xFAFAD2, "lightgray": 0xD3D3D3,
        "lightgreen": 0x90EE90, "lightgrey": 0xD3D3D3, "lightpink": 0xFFB6C1, "lightsalmon": 0xFFA07A,
        "lightseagreen": 0x20B2AA, "lightskyblue": 0x87CEFA, "lightslategray": 0x778899, "lightslategrey": 0x778899,
        "lightsteelblue": 0xB0C4DE, "lightyellow": 0xFFFFE0, "lime": 0x00FF00, "limegreen": 0x32CD32,
        "linen": 0xFAF0E6, "magenta": 0xFF00FF, "maroon": 0x800000, "mediumaquamarine": 0x66CDAA,
        "mediumblue": 0x0000CD, "mediumorchid": 0xBA55D3, "mediumpurple": 0x9370DB, "mediumseagreen": 0x3CB371,
        "mediumslateblue": 0x7B68EE, "mediumspringgreen": 0x00FA9A, "mediumturquoise": 0x48D1CC, "mediumvioletred": 0xC71585,
        "midnightblue": 0x191970, "mintcream": 0xF5FFFA, "mistyrose": 0xFFE4E1, "moccasin": 0xFFE4B5,
        "navajowhite": 0xFFDEAD, "navy": 0x000080, "oldlace": 0xFDF5E6, "olive": 0x808000,
        "olivedrab": 0x6B8E23, "orange": 0xFFA500, "orangered": 0xFF4500, "orchid": 0xDA70D6,
        "palegoldenrod": 0xEEE8AA, "palegreen": 0x98FB98, "paleturquoise": 0xAFEEEE, "palevioletred": 0xDB7093,
        "papayawhip": 0xFFEFD5, "peachpuff": 0xFFDAB9, "peru": 0xCD853F, "pink": 0xFFC0CB,
        "plum": 0xDDA0DD, "powderblue": 0xB0E0E6, "purple": 0x800080, "rebeccapurple": 0x663399,
        "red": 0xFF0000, "rosybrown": 0xBC8F8F, "royalblue": 0x4169E1, "saddlebrown": 0x8B4513,
        "salmon": 0xFA8072, "sandybrown": 0xF4A460, "seagreen": 0x2E8B57, "seashell": 0xFFF5EE,
        "sienna": 0xA0522D, "silver": 0xC0C0C0, "skyblue": 0x87CEEB, "slateblue": 0x6A5ACD,
        "slategray": 0x708090, "slategrey": 0x708090, "snow": 0xFFFAFA, "springgreen": 0x00FF7F,
        "steelblue": 0x4682B4, "tan": 0xD2B48C, "teal": 0x008080, "thistle": 0xD8BFD8,
        "tomato": 0xFF6347, "turquoise": 0x40E0D0, "violet": 0xEE82EE, "wheat": 0xF5DEB3,
        "white": 0xFFFFFF, "whitesmoke": 0xF5F5F5, "yellow": 0xFFFF00, "yellowgreen": 0x9ACD32,
    ]
}
