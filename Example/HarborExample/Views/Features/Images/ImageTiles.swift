//
//  ImageTiles.swift
//  HarborExample
//
//  Layout building blocks of the HarborImage demo sections
//

import SwiftUI
import HarborImage

/// Four demo slots per row that share the width of the section, so a section is never wider
/// than the screen.
struct ImageCaptionGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 4), spacing: 16) {
            content
        }
    }
}

/// A square demo slot (at most 80 pt) with a caption below it and, when known, where its
/// image came from.
struct ImageCaption<Content: View>: View {
    let title: String
    let source: HImageSource?
    @ViewBuilder let content: Content

    init(_ title: String, source: HImageSource? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.source = source
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 80)
                .overlay(content)
                .clipped()
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if let source {
                Text("from \(source.rawValue)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.accentColor)
            }
        }
    }
}

/// The same photo with a list of processors, shown 96 pt wide.
struct ImageProcessorTile: View {
    let title: String
    let processors: [any HImageProcessor]

    init(_ title: String, _ processors: [any HImageProcessor]) {
        self.title = title
        self.processors = processors
    }

    var body: some View {
        VStack(spacing: 6) {
            HImageView(url: ImageDemo.photos[7]) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView()
            }
            .processors([.resize(to: ImageDemo.square, mode: .fit)] + processors)
            .frame(width: 96, height: 96)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

/// A photo that always loads again, so its transition plays on every reload.
struct ImageTransitionTile: View {
    let title: String
    let transition: HImageTransition

    init(_ title: String, _ transition: HImageTransition) {
        self.title = title
        self.transition = transition
    }

    var body: some View {
        VStack(spacing: 6) {
            HImageView(url: ImageDemo.photos[9]) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .cachePolicy(.reloadIgnoringCache)
            .transition(transition)
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

/// The animated GIF at 80 pt with the given playback.
struct ImageGIF: View {
    let playback: HAnimatedImagePlayback
    let onSuccess: @MainActor (HImageResult) -> Void

    init(_ playback: HAnimatedImagePlayback, onSuccess: @escaping @MainActor (HImageResult) -> Void = { _ in }) {
        self.playback = playback
        self.onSuccess = onSuccess
    }

    var body: some View {
        HImageView(url: ImageDemo.gifURL) { phase in
            switch phase {
            case .empty(let progress): ProgressView(value: progress ?? 0)
            case .success(let image): image.resizable().scaledToFit()
            case .failure(let error): Text(error.localizedDescription).font(.caption2)
            }
        }
        .downsampling(to: CGSize(width: 80, height: 80), contentMode: .fit)
        .animatedPlayback(playback)
        .onSuccess(onSuccess)
    }
}
