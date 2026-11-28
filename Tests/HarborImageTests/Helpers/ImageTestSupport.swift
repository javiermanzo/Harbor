//
//  ImageTestSupport.swift
//  HarborImageTests
//
//  Shared fixtures: images generated in code (no binary files), pixel sampling, a fake
//  connectivity monitor, auth providers and the configuration reset every suite uses.
//

import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import HarborCore
@testable import HarborImage

/// An RGBA color sampled from an image, components in 0...255.
struct RGBA: Equatable, CustomStringConvertible {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Int

    var description: String { "rgba(\(red),\(green),\(blue),\(alpha))" }

    /// Whether every component is within `tolerance` of the other color.
    func isClose(to other: RGBA, tolerance: Int = 8) -> Bool {
        abs(red - other.red) <= tolerance && abs(green - other.green) <= tolerance
            && abs(blue - other.blue) <= tolerance && abs(alpha - other.alpha) <= tolerance
    }

    static let red = RGBA(red: 255, green: 0, blue: 0, alpha: 255)
    static let green = RGBA(red: 0, green: 255, blue: 0, alpha: 255)
    static let blue = RGBA(red: 0, green: 0, blue: 255, alpha: 255)
    static let white = RGBA(red: 255, green: 255, blue: 255, alpha: 255)
    static let black = RGBA(red: 0, green: 0, blue: 0, alpha: 255)
    static let clear = RGBA(red: 0, green: 0, blue: 0, alpha: 0)
}

enum TestImages {
    /// A solid image, optionally with a second color in the left half.
    static func image(width: Int, height: Int, color: RGBA = .red, leftHalf: RGBA? = nil) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let leftHalf {
            context.setFillColor(leftHalf.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        }
        return context.makeImage()!
    }

    /// Encodes an image.
    static func encode(_ image: CGImage, type: String = "public.png", properties: [CFString: Any] = [:]) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// A PNG of a solid image.
    static func png(width: Int = 40, height: Int = 20, color: RGBA = .red, leftHalf: RGBA? = nil) -> Data {
        encode(image(width: width, height: height, color: color, leftHalf: leftHalf))
    }

    /// A JPEG of a solid image.
    static func jpeg(width: Int = 40, height: Int = 20, color: RGBA = .red, orientation: Int? = nil) -> Data {
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        return encode(image(width: width, height: height, color: color), type: "public.jpeg", properties: properties)
    }

    /// An animated GIF with one solid frame per color; a `nil` loop count writes no loop extension.
    static func gif(colors: [RGBA], delay: Double = 0.05, loopCount: Int? = 0, size: Int = 8) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "com.compuserve.gif" as CFString, colors.count, nil)!
        if let loopCount {
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopCount]] as CFDictionary)
        }
        for color in colors {
            CGImageDestinationAddImage(destination, image(width: size, height: size, color: color),
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// An ICO holding one solid image per size.
    static func ico(sizes: [Int], color: RGBA = .red) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "com.microsoft.ico" as CFString, sizes.count, nil)!
        for size in sizes {
            CGImageDestinationAddImage(destination, image(width: size, height: size, color: color), nil)
        }
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// Samples one pixel (origin at the top left), unpremultiplied.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> RGBA {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        let alpha = Int(bytes[3])
        func unpremultiply(_ value: UInt8) -> Int {
            alpha == 0 ? 0 : min(255, Int((Double(value) * 255 / Double(alpha)).rounded()))
        }
        return RGBA(red: unpremultiply(bytes[0]), green: unpremultiply(bytes[1]), blue: unpremultiply(bytes[2]), alpha: alpha)
    }
}

extension RGBA {
    var cgColor: CGColor {
        CGColor(srgbRed: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, alpha: Double(alpha) / 255)
    }
}

/// Connectivity monitor with a configurable answer.
final class FakeImageConnectivityMonitor: HRequestManagerMonitorProtocol {
    var connected: Bool

    init(connected: Bool) {
        self.connected = connected
    }

    func start() {}

    func isConnectedToNetwork() -> Bool {
        connected
    }
}

/// Auth provider whose header rotates on every `authFailed()`.
actor RotatingImageAuthProvider: HAuthProviderProtocol {
    private(set) var refreshCount = 0
    private var token = "token-0"

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        HAuthorizationHeader(key: "Authorization", value: "Bearer \(token)")
    }

    func authFailed() async {
        refreshCount += 1
        token = "token-\(refreshCount)"
    }
}

/// A request that opts into debug logging.
struct DebugImageRequest: HImageRequestProtocol, HDebugRequestProtocol {
    let url: String
}

/// A custom processor that paints the image a solid color.
struct SolidColorProcessor: HImageProcessor {
    let color: RGBA
    var identifier: String { "solid(\(color))" }

    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        TestImages.image(width: image.width, height: image.height, color: color)
    }
}

/// A processor that always throws.
struct FailingProcessor: HImageProcessor {
    struct Failure: Error {}
    var identifier: String { "failing" }

    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        throw Failure()
    }
}

@HRequestManagerActor
enum ImageTestDefaults {
    /// Resets HarborImage and the shared configuration it uses: stubs installed, connected,
    /// a fresh cache directory, default settings, no auth, mocks enabled with none registered,
    /// empty cache.
    static func restore(directory: URL? = nil) async {
        ImageStubProtocol.reset()
        Harbor.setProtocolClasses([ImageStubProtocol.self])
        Harbor.setAuthProvider(nil)
        Harbor.setDefaultHeaderParameters(nil)
        Harbor.setDefaultTimeoutInterval(15)
        HConfig.shared.customURLSession = nil
        HRequestManager.connectivityMonitor = FakeImageConnectivityMonitor(connected: true)
        HarborImage.setCacheConfiguration(HImageCache.Configuration(directory: directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("HarborImageTests-\(UUID().uuidString)", isDirectory: true)))
        HarborImage.setDefaultCacheType(.memoryAndDisk)
        HarborImage.setDefaultRetryPolicy(nil)
        HarborImage.setMaxDownloadSizeInMBs(30)
        HarborImage.setMaxImagePixels(100_000_000)
        HarborImage.setMaxConcurrentDownloads(6)
        HarborImage.removeAllDecoders()
        HarborImage.removeAllMocks()
        HarborImage.setMocksEnabled(true)
        await HarborImage.clearCache()
    }

    /// Restores the defaults the other test targets expect.
    static func tearDown() async {
        await HarborImage.clearCache()
        ImageStubProtocol.reset()
        Harbor.setProtocolClasses(nil)
        Harbor.setAuthProvider(nil)
        HRequestManager.connectivityMonitor = HRequestManagerMonitor()
        HarborImage.setCacheConfiguration(HImageCache.Configuration())
        HarborImage.removeAllMocks()
        HarborImage.removeAllDecoders()
    }
}

/// The URL of a stubbed path.
func imageURL(_ path: String) -> String {
    "https://images.test\(path)"
}
