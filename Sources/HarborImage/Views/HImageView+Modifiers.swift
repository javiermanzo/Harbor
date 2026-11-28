//
//  HImageView+Modifiers.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import HarborCore
import SwiftUI

// MARK: - Request Modifiers

public extension HImageView {
    /// Replaces the processors of the request.
    /// - Parameter processors: The processors, applied in order.
    func processors(_ processors: [any HImageProcessor]) -> HImageView {
        var view = self
        view.request.processorsOverride = processors
        return view
    }

    /// Sets the encoding (compression and format conversion) of the result's data and of the
    /// variant stored on disk, with or without processors.
    /// - Parameter encoding: The encoding.
    func encoding(_ encoding: HImageEncoding) -> HImageView {
        var view = self
        view.request.encodingOverride = encoding
        return view
    }

    /// Sets where the image is cached.
    /// - Parameter cacheType: The cache type.
    func cacheType(_ cacheType: HImageCacheType) -> HImageView {
        var view = self
        view.request.cacheTypeOverride = cacheType
        return view
    }

    /// Sets whether the cache is read before downloading.
    /// - Parameter cachePolicy: The cache policy.
    func cachePolicy(_ cachePolicy: HImageCachePolicy) -> HImageView {
        var view = self
        view.request.cachePolicyOverride = cachePolicy
        return view
    }

    /// Sets the retry policy of the download.
    /// - Parameter retryPolicy: The retry policy.
    func retryPolicy(_ retryPolicy: HRetryPolicy) -> HImageView {
        var view = self
        view.request.retryPolicyOverride = retryPolicy
        return view
    }

    /// Decodes the image at the size it is displayed at, in points (converted to pixels with
    /// the display scale), instead of its full size. Use it in lists and grids: a large photo
    /// shown as a thumbnail then takes a fraction of the memory. The image scale becomes the
    /// display scale.
    /// - Parameters:
    ///   - size: The displayed size in points.
    ///   - contentMode: How the image fills the size. Default: `.fill`.
    func downsampling(to size: CGSize, contentMode: HImageTargetSize.ContentMode = .fill) -> HImageView {
        var view = self
        view.options.downsampling = HImageViewOptions.Downsampling(size: size, contentMode: contentMode)
        return view
    }
}

// MARK: - Presentation Modifiers

public extension HImageView {
    /// Sets the transition from the placeholder to the image. Default: `.none`.
    /// - Parameter transition: The transition.
    func transition(_ transition: HImageTransition) -> HImageView {
        var view = self
        view.options.transition = transition
        return view
    }

    /// Sets how an animated image plays. Default: `.automatic`.
    /// - Parameter playback: The playback configuration.
    func animatedPlayback(_ playback: HAnimatedImagePlayback) -> HImageView {
        var view = self
        view.options.playback = playback
        return view
    }

    /// Sets the scale of the image (pixels per point) when not downsampling. Default: 1.
    /// - Parameter scale: The scale.
    func imageScale(_ scale: CGFloat) -> HImageView {
        var view = self
        view.options.scale = scale.isFinite && scale > 0 ? scale : 1
        return view
    }

    /// Gives the image an accessibility label; without one it is decorative.
    /// - Parameter label: The label.
    func imageAccessibilityLabel(_ label: Text) -> HImageView {
        var view = self
        view.options.accessibilityLabel = label
        return view
    }
}

// MARK: - Callbacks

public extension HImageView {
    /// Calls `action` on the main actor when the image is shown (also when it comes from the
    /// memory cache). The callback is optional: the phase already reflects the outcome.
    /// - Parameter action: Receives the result.
    func onSuccess(_ action: @escaping @MainActor (HImageResult) -> Void) -> HImageView {
        var view = self
        view.options.onSuccess = action
        return view
    }

    /// Calls `action` on the main actor when the load fails (not when it is cancelled).
    /// - Parameter action: Receives the error.
    func onFailure(_ action: @escaping @MainActor (HImageError) -> Void) -> HImageView {
        var view = self
        view.options.onFailure = action
        return view
    }

    /// Calls `action` on the main actor with the download progress in `0...1`, when the server
    /// announces the size.
    /// - Parameter action: Receives the progress.
    func onProgress(_ action: @escaping @MainActor (Double) -> Void) -> HImageView {
        var view = self
        view.options.onProgress = action
        return view
    }
}
