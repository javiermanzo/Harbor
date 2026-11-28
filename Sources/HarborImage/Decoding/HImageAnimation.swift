//
//  HImageAnimation.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import Foundation
import HarborCore
import ImageIO

/// The frames of an animated image (GIF, APNG, animated WebP). Frames are decoded on demand
/// and only a few are kept in memory, so a long animation does not hold every frame.
/// `HImageView` plays it on its own; to render it yourself, read `frameCount`,
/// `frameDurations` and `frame(at:)`.
public final class HImageAnimation: Sendable {
    /// Number of frames.
    public let frameCount: Int
    /// How long each frame is shown, in seconds.
    public let frameDurations: [TimeInterval]
    /// How many times the animation plays; `0` means forever. A GIF without a loop count plays once.
    public let loopCount: Int

    /// The encoded animation.
    private let source: HLockedState<HImageSourceBox>
    /// The size frames are decoded at, or `nil` for the full size.
    private let maxPixelSize: Int?
    /// Processors applied to every frame.
    private let processors: [any HImageProcessor]
    /// The processing context of the frames.
    private let context: HImageProcessingContext
    /// Recently decoded frames, by index.
    private let frames = HLockedState(HImageFrameCache())

    /// Creates an animation from an image source with more than one frame.
    /// - Parameters:
    ///   - source: The image source.
    ///   - maxPixelSize: The size frames are decoded at, or `nil` for the full size.
    ///   - processors: Processors applied to every frame.
    ///   - context: The processing context of the frames.
    ///   - firstFrame: The already decoded and processed first frame.
    init?(source: CGImageSource, maxPixelSize: Int?, processors: [any HImageProcessor], context: HImageProcessingContext, firstFrame: CGImage) {
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }
        self.frameCount = count
        self.frameDurations = (0..<count).map { Self.duration(source: source, index: $0) }
        self.loopCount = Self.loopCount(source: source)
        self.source = HLockedState(HImageSourceBox(source: source))
        self.maxPixelSize = maxPixelSize
        self.processors = processors
        self.context = context
        frames.withLock { $0.insert(firstFrame, at: 0) }
    }
}

// MARK: - Frames

public extension HImageAnimation {
    /// The total duration of one loop, in seconds.
    var duration: TimeInterval {
        frameDurations.reduce(0, +)
    }

    /// Decodes (and processes) a frame, off the main actor.
    /// - Parameter index: The frame index, in `0..<frameCount`.
    /// - Returns: The frame, or `nil` when it cannot be decoded, a processor throws, or the index
    ///   is out of range.
    func frame(at index: Int) async -> CGImage? {
        guard (0..<frameCount).contains(index) else { return nil }
        if let cached = frames.withLock({ $0.frame(at: index) }) {
            return cached
        }
        guard var image = source.withLock({ box in
            HImageIODecoder.decodeFrame(source: box.source, index: index, maxPixelSize: maxPixelSize)
        }) else {
            return nil
        }
        for processor in processors {
            guard let processed = try? await processor.process(image, context: context) else { return nil }
            image = processed
        }
        frames.withLock { $0.insert(image, at: index) }
        return image
    }
}

// MARK: - Frame Properties

extension HImageAnimation {
    /// Decoded frames kept at once, the first one included; the memory cache counts them in the
    /// cost of an animated image.
    static let maxCachedFrames = 8

    /// Shortest frame duration honored; shorter (or missing) delays are shown for 0.1 s, as browsers do.
    private static let minimumFrameDuration: TimeInterval = 0.011

    /// The duration of a frame, from its GIF, PNG or WebP properties.
    /// - Parameters:
    ///   - source: The image source.
    ///   - index: The frame index.
    private static func duration(source: CGImageSource, index: Int) -> TimeInterval {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        // Per format: its properties dictionary, then the unclamped and the clamped delay keys.
        let containers: [(CFString, [CFString])] = [
            (kCGImagePropertyGIFDictionary, [kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime]),
            (kCGImagePropertyPNGDictionary, [kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime]),
            (kCGImagePropertyWebPDictionary, [kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime]),
        ]
        for (container, keys) in containers {
            guard let dictionary = properties[container] as? [CFString: Any] else { continue }
            let value = keys.lazy.compactMap { dictionary[$0] as? Double }.first ?? 0
            return value < minimumFrameDuration ? 0.1 : value
        }
        return 0.1
    }

    /// How many times the animation plays, `0` for forever. A GIF without a loop count (no
    /// NETSCAPE extension) plays once, as browsers do; APNG and WebP always store one.
    /// - Parameter source: The image source.
    private static func loopCount(source: CGImageSource) -> Int {
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any] ?? [:]
        let containers: [(CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFLoopCount),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGLoopCount),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPLoopCount),
        ]
        for (container, key) in containers {
            if let dictionary = properties[container] as? [CFString: Any], let count = dictionary[key] as? Int {
                return max(0, count)
            }
        }
        let isGIF = (CGImageSourceGetType(source) as String?) == "com.compuserve.gif"
        return isGIF ? 1 : 0
    }
}

// MARK: - Source Box

/// An image source, only accessed while holding the animation's lock.
private struct HImageSourceBox: @unchecked Sendable {
    /// The image source. ImageIO does not document a source as safe to use from several
    /// threads at once, so every access goes through `HLockedState`.
    let source: CGImageSource
}

// MARK: - Frame Cache

/// The last decoded frames of an animation, bounded so a long animation does not hold every frame.
private struct HImageFrameCache: Sendable {
    /// Frames kept at once.
    private static let capacity = HImageAnimation.maxCachedFrames
    /// The frames, by index.
    private var frames: [Int: CGImage] = [:]
    /// Frame indices from least to most recently inserted.
    private var order: [Int] = []

    /// The cached frame at the index.
    /// - Parameter index: The frame index.
    func frame(at index: Int) -> CGImage? {
        frames[index]
    }

    /// Caches a frame, evicting the oldest one past the capacity. Frame 0 is kept, so a
    /// paused or restarted animation shows it at once.
    /// - Parameters:
    ///   - frame: The frame.
    ///   - index: The frame index.
    mutating func insert(_ frame: CGImage, at index: Int) {
        if frames.updateValue(frame, forKey: index) == nil {
            order.append(index)
        }
        while order.count > Self.capacity, let victim = order.first(where: { $0 != 0 }) {
            order.removeAll { $0 == victim }
            frames[victim] = nil
        }
    }
}
