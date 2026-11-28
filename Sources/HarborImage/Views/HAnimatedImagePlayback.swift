//
//  HAnimatedImagePlayback.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// How `HImageView` plays an animated image (GIF, APNG, animated WebP). Playback stops when the
/// view leaves the screen and starts over from the first frame when it comes back. To render
/// the frames yourself, disable it and read `HImageResult.animation` (from `.onSuccess` or
/// `HarborImage.image(for:)`).
public struct HAnimatedImagePlayback: Sendable, Hashable {
    /// Whether the animation plays; when `false` the first frame is shown.
    public let isEnabled: Bool
    /// How many times it plays, `0` for forever; `nil` uses the loop count stored in the image.
    public let loopCount: Int?
    /// The speed multiplier: 2 plays twice as fast.
    public let speed: Double

    /// Creates a playback configuration.
    /// - Parameters:
    ///   - isEnabled: Whether the animation plays. Default: `true`.
    ///   - loopCount: How many times it plays, `0` for forever; negative values become 0.
    ///     Default: `nil`, the image's own (once for a GIF without a loop count).
    ///   - speed: The speed multiplier. Default: 1. Values that are not finite and positive become 1.
    public init(isEnabled: Bool = true, loopCount: Int? = nil, speed: Double = 1) {
        self.isEnabled = isEnabled
        self.loopCount = loopCount.map { max(0, $0) }
        self.speed = speed.isFinite && speed > 0 ? speed : 1
    }
}

// MARK: - Presets

public extension HAnimatedImagePlayback {
    /// Plays as the image says (default).
    static let automatic = HAnimatedImagePlayback()
    /// Shows the first frame only.
    static let disabled = HAnimatedImagePlayback(isEnabled: false)
}
