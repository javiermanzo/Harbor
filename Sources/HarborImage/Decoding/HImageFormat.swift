//
//  HImageFormat.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// An image format, detected from the bytes (magic numbers), never from the `Content-Type`
/// header or the file extension. A custom `HImageDecoder` declares its own format.
public struct HImageFormat: RawRepresentable, Sendable, Hashable {
    /// The format name, e.g. `"jpeg"`.
    public let rawValue: String

    /// Creates a format from its name.
    /// - Parameter rawValue: The format name.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

// MARK: - Known Formats

public extension HImageFormat {
    /// JPEG.
    static let jpeg = HImageFormat(rawValue: "jpeg")
    /// PNG, including animated PNG (APNG).
    static let png = HImageFormat(rawValue: "png")
    /// GIF, still or animated.
    static let gif = HImageFormat(rawValue: "gif")
    /// WebP, still or animated (decoding only).
    static let webp = HImageFormat(rawValue: "webp")
    /// HEIC / HEIF.
    static let heic = HImageFormat(rawValue: "heic")
    /// AVIF, where the system supports it.
    static let avif = HImageFormat(rawValue: "avif")
    /// TIFF.
    static let tiff = HImageFormat(rawValue: "tiff")
    /// BMP.
    static let bmp = HImageFormat(rawValue: "bmp")
    /// ICO.
    static let ico = HImageFormat(rawValue: "ico")
    /// SVG, rasterized by HarborImage's own renderer.
    static let svg = HImageFormat(rawValue: "svg")
}

// MARK: - Detection

extension HImageFormat {
    /// Detects the format of the bytes from their signature.
    /// - Parameter data: The image bytes.
    /// - Returns: The format, or `nil` when the bytes are not a known image format.
    static func detect(_ data: Data) -> HImageFormat? {
        let bytes = [UInt8](data.prefix(32))
        func starts(_ signature: [UInt8], at offset: Int = 0) -> Bool {
            guard bytes.count >= offset + signature.count else { return false }
            return Array(bytes[offset..<(offset + signature.count)]) == signature
        }

        if starts([0xFF, 0xD8, 0xFF]) { return .jpeg }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if starts(Array("GIF87a".utf8)) || starts(Array("GIF89a".utf8)) { return .gif }
        if starts(Array("RIFF".utf8)), starts(Array("WEBP".utf8), at: 8) { return .webp }
        if starts(Array("ftyp".utf8), at: 4), bytes.count >= 12 {
            let brand = String(bytes: bytes[8..<12], encoding: .ascii) ?? ""
            if ["avif", "avis"].contains(brand) { return .avif }
            if ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"].contains(brand) { return .heic }
        }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
        if starts(Array("BM".utf8)) { return .bmp }
        if starts([0x00, 0x00, 0x01, 0x00]) { return .ico }
        if HSVGSniffer.isSVG(data) { return .svg }
        return nil
    }

    /// The uniform type identifier ImageIO uses for the format, when it has one.
    var typeIdentifier: String? {
        switch self {
        case .jpeg: return "public.jpeg"
        case .png: return "public.png"
        case .gif: return "com.compuserve.gif"
        case .webp: return "org.webmproject.webp"
        case .heic: return "public.heic"
        case .avif: return "public.avif"
        case .tiff: return "public.tiff"
        case .bmp: return "com.microsoft.bmp"
        case .ico: return "com.microsoft.ico"
        default: return nil
        }
    }
}
