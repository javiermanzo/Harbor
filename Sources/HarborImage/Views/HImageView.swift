//
//  HImageView.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import CoreGraphics
import HarborCore
import SwiftUI

/// Loads and shows an image through HarborImage: Harbor's pipeline (auth, retry, pinning, mTLS),
/// the memory and disk cache, processors, animated images and transitions.
///
/// ```swift
/// // Content and placeholder, like AsyncImage
/// HImageView(url: "https://cdn.example.com/a.jpg") { image in
///     image.resizable().scaledToFill()
/// } placeholder: {
///     ProgressView()
/// }
///
/// // One closure per phase
/// HImageView(request: AvatarRequest(userId: 7)) { phase in
///     switch phase {
///     case .empty(let progress): ProgressView(value: progress ?? 0)
///     case .success(let image): image.resizable().scaledToFit()
///     case .failure(let error): Text(error.localizedDescription)
///     }
/// }
/// .processors([.resize(to: CGSize(width: 240, height: 240), mode: .fill), .mask(.circle)])
/// .transition(.fade())
/// .onSuccess { result in print(result.source) }
/// ```
///
/// An image in the memory cache is shown in the first render, without the placeholder. The load
/// runs while the view is on screen: leaving the screen cancels it (other views loading the same
/// image keep their download) and stops an animated image, which starts over from the first
/// frame when the view comes back.
public struct HImageView<Content: View>: View {
    /// The request with the view's modifiers applied.
    var request: HImageViewRequest
    /// The view's options (transition, playback, callbacks, scale, label).
    var options = HImageViewOptions()
    /// Builds the content of a phase.
    private let content: (HImagePhase) -> Content

    /// The phase of the last load.
    @State private var phase: HImagePhase = .empty(progress: nil)
    /// The load key `phase` belongs to. When the request changes, the view shows the new image
    /// from memory, or an empty phase, instead of the previous request's image or error.
    @State private var phaseKey: String?
    /// The display scale, for `.downsampling(to:contentMode:)` and the image scale.
    @Environment(\.displayScale) private var displayScale

    /// Creates a view whose content depends on the phase.
    /// - Parameters:
    ///   - request: The image to load.
    ///   - content: Builds the content of each phase.
    public init(request: some HImageRequestProtocol, @ViewBuilder content: @escaping (HImagePhase) -> Content) {
        self.request = HImageViewRequest(base: request)
        self.content = content
    }

    /// Creates a view whose content depends on the phase.
    /// - Parameters:
    ///   - url: The image URL.
    ///   - content: Builds the content of each phase.
    public init(url: String, @ViewBuilder content: @escaping (HImagePhase) -> Content) {
        self.init(request: HImageRequest(url: url), content: content)
    }

    /// Creates a view that shows the image, or a placeholder while it loads or when it fails.
    /// - Parameters:
    ///   - request: The image to load.
    ///   - content: Builds the content from the image.
    ///   - placeholder: Shown while loading and on failure.
    public init<I: View, P: View>(request: some HImageRequestProtocol,
                                  @ViewBuilder content: @escaping (Image) -> I,
                                  @ViewBuilder placeholder: @escaping () -> P) where Content == _ConditionalContent<I, P> {
        self.init(request: request) { phase in
            Self.imageOrPlaceholder(phase, content: content, placeholder: placeholder)
        }
    }

    /// Creates a view that shows the image, or a placeholder while it loads or when it fails.
    /// - Parameters:
    ///   - url: The image URL.
    ///   - content: Builds the content from the image.
    ///   - placeholder: Shown while loading and on failure.
    public init<I: View, P: View>(url: String,
                                  @ViewBuilder content: @escaping (Image) -> I,
                                  @ViewBuilder placeholder: @escaping () -> P) where Content == _ConditionalContent<I, P> {
        self.init(request: HImageRequest(url: url), content: content, placeholder: placeholder)
    }

    /// Creates a view that shows the image at its size, and a light gray placeholder.
    /// - Parameter url: The image URL.
    public init(url: String) where Content == _ConditionalContent<Image, Color> {
        self.init(request: HImageRequest(url: url), content: { $0 }, placeholder: { Color.gray.opacity(0.2) })
    }

    /// The content.
    public var body: some View {
        let key = loadKey
        let current = phaseKey == key ? phase : .empty(progress: nil)
        let shown = current.isEmpty ? (cachedPhase(forKey: key) ?? current) : current
        ZStack {
            content(shown)
                .id(shown.kind)
                .transition(options.transition.transition)
        }
        .task(id: key) {
            await load()
        }
    }
}

// MARK: - Loading

extension HImageView {
    /// The request as loaded, with the downsampling size computed from the display scale.
    private var effectiveRequest: HImageViewRequest {
        var effective = request
        if let downsampling = options.downsampling {
            effective.targetSizeOverride = HImageTargetSize(size: downsampling.size, scale: displayScale, contentMode: downsampling.contentMode)
        }
        return effective
    }

    /// Identifies the load: the cache policy and the memory key (URL or `cacheKey`, processors,
    /// encoding, decoding size). A change restarts it; changing the cache type, retry policy,
    /// headers or `needsAuth` of a view on screen does not.
    private var loadKey: String {
        let effective = effectiveRequest
        guard let resolved = try? HImageResolvedRequest(request: effective, defaultCacheType: .memoryAndDisk, defaultRetryPolicy: nil) else {
            return "invalid|" + effective.url
        }
        return resolved.cachePolicy.rawValue + "|" + resolved.key.memory
    }

    /// The image scale: the display scale when downsampling, otherwise the view's scale.
    private var imageScale: CGFloat {
        options.downsampling != nil ? displayScale : options.scale
    }

    /// The image in the memory cache, read synchronously so it shows in the first render.
    /// - Parameter key: The load key.
    private func cachedPhase(forKey key: String) -> HImagePhase? {
        guard let result = cachedResult(forKey: key) else { return nil }
        return .success(makeImage(result.image))
    }

    /// The result in the memory cache for the load key, unless the request bypasses memory.
    /// - Parameter key: The load key.
    private func cachedResult(forKey key: String) -> HImageResult? {
        let effective = effectiveRequest
        guard effective.cachePolicy != .reloadIgnoringCache,
              effective.cacheType.map(\.usesMemory) ?? true,
              let separator = key.firstIndex(of: "|") else {
            return nil
        }
        return HImageMemoryCache.shared.result(forKey: String(key[key.index(after: separator)...]))
    }

    /// Loads the image, then plays it when it is animated.
    private func load() async {
        let effective = effectiveRequest
        let key = loadKey
        if let cached = cachedResult(forKey: key) {
            show(.success(makeImage(cached.image)), for: key)
            options.onSuccess?(cached.with(source: .memory))
            await play(cached, key: key)
            return
        }

        show(.empty(progress: nil), for: key)
        var response: HImageResponse?
        for await event in HarborImage.events(for: effective) {
            switch event {
            case .progress(let fraction):
                show(.empty(progress: fraction), for: key)
                options.onProgress?(fraction)
            case .finished(let finished):
                response = finished
            default:
                break
            }
        }
        guard !Task.isCancelled, let response else { return }

        switch response {
        case .success(let result):
            let image = makeImage(result.image)
            if result.source == .memory || options.transition.animation == nil {
                show(.success(image), for: key)
            } else {
                withAnimation(options.transition.animation) {
                    show(.success(image), for: key)
                }
            }
            options.onSuccess?(result)
            await play(result, key: key)
        case .failure(let error):
            guard error != .cancelled else { return }
            withAnimation(options.transition.animation) {
                show(.failure(error), for: key)
            }
            options.onFailure?(error)
        }
    }

    /// Sets the phase and the load key it belongs to.
    /// - Parameters:
    ///   - newPhase: The phase.
    ///   - key: The load key.
    private func show(_ newPhase: HImagePhase, for key: String) {
        phase = newPhase
        phaseKey = key
    }

    /// Plays an animated image until the task is cancelled or the loops are done. Leaving the
    /// screen cancels the task; when the view comes back, playback starts over from the first frame.
    /// - Parameters:
    ///   - result: The loaded image.
    ///   - key: The load key the frames belong to.
    private func play(_ result: HImageResult, key: String) async {
        guard let animation = result.animation, options.playback.isEnabled else { return }
        let loopLimit = options.playback.loopCount ?? animation.loopCount
        var loops = 0
        while !Task.isCancelled {
            for index in 0..<animation.frameCount {
                guard let frame = await animation.frame(at: index), !Task.isCancelled else {
                    if Task.isCancelled { return }
                    continue
                }
                show(.success(makeImage(frame)), for: key)
                let delay = animation.frameDurations[index] / options.playback.speed
                guard await HImageView.sleep(seconds: delay) else { return }
            }
            loops += 1
            if loopLimit > 0, loops >= loopLimit { return }
        }
    }

    /// Builds the SwiftUI image, decorative unless the view has an accessibility label.
    /// - Parameter cgImage: The image.
    private func makeImage(_ cgImage: CGImage) -> Image {
        if let label = options.accessibilityLabel {
            return Image(cgImage, scale: imageScale, label: label)
        }
        return Image(decorative: cgImage, scale: imageScale)
    }

    /// Sleeps for the given seconds.
    /// - Parameter seconds: The duration.
    /// - Returns: `false` when the task was cancelled.
    private static func sleep(seconds: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            return true
        } catch {
            return false
        }
    }

    /// The content of the content-and-placeholder initializers.
    /// - Parameters:
    ///   - phase: The phase.
    ///   - content: Builds the content from the image.
    ///   - placeholder: Shown while loading and on failure.
    @ViewBuilder
    private static func imageOrPlaceholder<I: View, P: View>(_ phase: HImagePhase, content: (Image) -> I, placeholder: () -> P) -> _ConditionalContent<I, P> {
        if let image = phase.image {
            content(image)
        } else {
            placeholder()
        }
    }
}
