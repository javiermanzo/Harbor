//
//  HImageEncoding.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// Compression and format conversion: the last stage of a load, after the processors. It sets
/// the bytes of `HImageResult.data` and of the processed variant stored on disk, and is
/// available on its own through `HarborImage.encode(_:as:)`.
///
/// Re-encoding never copies the original metadata (EXIF, GPS). WebP is decoded but cannot be
/// produced: ImageIO has no WebP encoder.
///
/// ```swift
/// HImageRequest(url: url, processors: [.resize(to: CGSize(width: 1024, height: 1024))],
///               encoding: .jpeg(quality: 0.8, maxBytes: 200_000))
/// ```
public struct HImageEncoding: Sendable, Hashable {
    /// An output format.
    public enum Format: String, Sendable, Hashable {
        /// JPEG, lossy, without alpha (transparent pixels become black).
        case jpeg
        /// PNG, lossless, with alpha.
        case png
        /// HEIC, lossy, with alpha. Not every device can encode it: it fails with
        /// `.encodingFailed` where it cannot.
        case heic
    }

    /// The output format.
    public let format: Format
    /// The compression quality in `0...1` (ignored by PNG).
    public let quality: Double
    /// The largest output accepted in bytes (values below 1 become 1): the quality is lowered,
    /// down to 0.05 (or the requested quality when lower), until the output fits, else the load
    /// fails with `.encodingFailed`. PNG, which has no quality, fails as soon as it is larger.
    /// `nil` for no limit.
    public let maxBytes: Int?

    /// Creates an encoding.
    /// - Parameters:
    ///   - format: The output format.
    ///   - quality: The compression quality in `0...1`. Default: 0.85.
    ///   - maxBytes: The largest output accepted in bytes. Default: `nil`.
    public init(format: Format, quality: Double = 0.85, maxBytes: Int? = nil) {
        self.format = format
        self.quality = quality.isFinite ? min(max(quality, 0), 1) : 0.85
        self.maxBytes = maxBytes.map { max(1, $0) }
    }
}

// MARK: - Factory

public extension HImageEncoding {
    /// JPEG at the given quality.
    /// - Parameters:
    ///   - quality: The compression quality in `0...1`. Default: 0.85.
    ///   - maxBytes: The largest output accepted in bytes. Default: `nil`.
    static func jpeg(quality: Double = 0.85, maxBytes: Int? = nil) -> HImageEncoding {
        HImageEncoding(format: .jpeg, quality: quality, maxBytes: maxBytes)
    }

    /// Lossless PNG.
    static var png: HImageEncoding {
        HImageEncoding(format: .png, quality: 1)
    }

    /// HEIC at the given quality.
    /// - Parameters:
    ///   - quality: The compression quality in `0...1`. Default: 0.85.
    ///   - maxBytes: The largest output accepted in bytes. Default: `nil`.
    static func heic(quality: Double = 0.85, maxBytes: Int? = nil) -> HImageEncoding {
        HImageEncoding(format: .heic, quality: quality, maxBytes: maxBytes)
    }
}

// MARK: - Identifier

extension HImageEncoding {
    /// The identifier of the encoding in cache keys.
    var identifier: String {
        "\(format.rawValue)(\(quality),\(maxBytes.map(String.init) ?? "-"))"
    }

    /// The format of the encoded bytes.
    var imageFormat: HImageFormat {
        switch format {
        case .jpeg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        }
    }
}
