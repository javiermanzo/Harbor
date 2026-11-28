//
//  HImageEncoder.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation
import ImageIO

/// Encodes images with ImageIO for `HImageEncoding`.
enum HImageEncoder {
    /// Lowest quality tried while looking for an output under `maxBytes`.
    private static let minimumQuality = 0.05
    /// Quality steps of the binary search for `maxBytes`.
    private static let searchSteps = 7

    /// Encodes the image.
    /// - Parameters:
    ///   - image: The image.
    ///   - encoding: The format, quality and size limit.
    /// - Throws: `.encodingFailed` when the format is unavailable or `maxBytes` cannot be met.
    static func encode(_ image: CGImage, as encoding: HImageEncoding) throws(HImageError) -> Data {
        let first = try encode(image, format: encoding.format, quality: encoding.quality)
        guard let maxBytes = encoding.maxBytes, first.count > maxBytes else {
            return first
        }
        guard encoding.format != .png else {
            throw .encodingFailed("The PNG is \(first.count) bytes, more than maxBytes (\(maxBytes)); PNG has no quality to lower")
        }

        // Binary search of the highest quality whose output fits.
        // A requested quality below the minimum is the floor of the search.
        let floor = min(minimumQuality, encoding.quality)
        var low = floor
        var high = encoding.quality
        var best: Data?
        for _ in 0..<searchSteps {
            let quality = (low + high) / 2
            let data = try encode(image, format: encoding.format, quality: quality)
            if data.count <= maxBytes {
                best = data
                low = quality
            } else {
                high = quality
            }
        }
        if let best { return best }
        let smallest = try encode(image, format: encoding.format, quality: floor)
        guard smallest.count <= maxBytes else {
            throw .encodingFailed("No quality fits in maxBytes (\(maxBytes)); the smallest output is \(smallest.count) bytes")
        }
        return smallest
    }

    /// Encodes the image once.
    /// - Parameters:
    ///   - image: The image.
    ///   - format: The output format.
    ///   - quality: The compression quality.
    private static func encode(_ image: CGImage, format: HImageEncoding.Format, quality: Double) throws(HImageError) -> Data {
        guard let type = format.typeIdentifier, isAvailable(type) else {
            throw .encodingFailed("This device cannot encode \(format.rawValue)")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type as CFString, 1, nil) else {
            throw .encodingFailed("Cannot create a \(format.rawValue) encoder")
        }
        var properties: [CFString: Any] = [:]
        if format != .png {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw .encodingFailed("The \(format.rawValue) encoder failed")
        }
        return data as Data
    }

    /// Whether ImageIO can write the type on this device.
    /// - Parameter type: The uniform type identifier.
    private static func isAvailable(_ type: String) -> Bool {
        (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(type)
    }
}

// MARK: - Type Identifiers

private extension HImageEncoding.Format {
    /// The uniform type identifier of the format.
    var typeIdentifier: String? {
        switch self {
        case .jpeg: return "public.jpeg"
        case .png: return "public.png"
        case .heic: return "public.heic"
        }
    }
}
