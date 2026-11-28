//
//  HImageTransition.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import SwiftUI

/// How `HImageView` moves from its placeholder to the image (and to the failure content). It
/// does not run when the image is shown from the memory cache in the first render, so cached
/// images in a list do not fade in again on every scroll.
///
/// ```swift
/// HImageView(url: url).transition(.fade(duration: 0.25))
/// HImageView(url: url).transition(.custom(.scale.combined(with: .opacity), animation: .spring))
/// ```
public struct HImageTransition {
    /// The SwiftUI transition applied to the phase content.
    let transition: AnyTransition
    /// The animation the phase change runs in, or `nil` for none.
    let animation: Animation?
}

// MARK: - Transitions

public extension HImageTransition {
    /// No transition (default): the image replaces the placeholder at once.
    static var none: HImageTransition {
        HImageTransition(transition: .identity, animation: nil)
    }

    /// A cross-fade.
    /// - Parameter duration: The duration in seconds. Default: 0.25.
    static func fade(duration: TimeInterval = 0.25) -> HImageTransition {
        HImageTransition(transition: .opacity, animation: .easeInOut(duration: duration))
    }

    /// A fade combined with a scale from `initialScale`.
    /// - Parameters:
    ///   - initialScale: The scale the image starts from. Default: 0.9.
    ///   - duration: The duration in seconds. Default: 0.3.
    static func scale(from initialScale: CGFloat = 0.9, duration: TimeInterval = 0.3) -> HImageTransition {
        HImageTransition(transition: .scale(scale: initialScale).combined(with: .opacity), animation: .easeOut(duration: duration))
    }

    /// The image comes into focus from a blur.
    /// - Parameters:
    ///   - radius: The initial blur radius in points. Default: 12.
    ///   - duration: The duration in seconds. Default: 0.35.
    static func blur(radius: CGFloat = 12, duration: TimeInterval = 0.35) -> HImageTransition {
        let blur = AnyTransition.modifier(active: HBlurTransitionModifier(radius: radius), identity: HBlurTransitionModifier(radius: 0))
        return HImageTransition(transition: blur.combined(with: .opacity), animation: .easeOut(duration: duration))
    }

    /// A custom transition.
    /// - Parameters:
    ///   - transition: Any SwiftUI transition.
    ///   - animation: The animation it runs in. Default: `.default`.
    static func custom(_ transition: AnyTransition, animation: Animation? = .default) -> HImageTransition {
        HImageTransition(transition: transition, animation: animation)
    }
}

// MARK: - Blur Modifier

/// Blurs the content, animatable between radii.
private struct HBlurTransitionModifier: ViewModifier {
    /// The blur radius in points.
    let radius: CGFloat

    /// Applies the blur.
    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}
