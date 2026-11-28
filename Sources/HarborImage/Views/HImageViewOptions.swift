//
//  HImageViewOptions.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import SwiftUI

/// The presentation options of an `HImageView`, set with its modifiers.
struct HImageViewOptions {
    /// A decoding size in points, converted to pixels with the display scale.
    struct Downsampling {
        /// The size in points.
        let size: CGSize
        /// How the image is scaled to the size.
        let contentMode: HImageTargetSize.ContentMode
    }

    /// The transition from the placeholder to the image.
    var transition: HImageTransition = .none
    /// How an animated image plays.
    var playback: HAnimatedImagePlayback = .automatic
    /// The decoding size, if any.
    var downsampling: Downsampling?
    /// The image scale when not downsampling.
    var scale: CGFloat = 1
    /// The accessibility label; the image is decorative without one.
    var accessibilityLabel: Text?
    /// Called on success.
    var onSuccess: (@MainActor (HImageResult) -> Void)?
    /// Called on failure (not on cancellation).
    var onFailure: (@MainActor (HImageError) -> Void)?
    /// Called with the download progress.
    var onProgress: (@MainActor (Double) -> Void)?
}
