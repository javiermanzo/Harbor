//
//  ImageSection.swift
//  HarborExample
//
//  Card with a reload button that wraps each HarborImage demo
//

import SwiftUI
import HarborImage

/// A section card whose header has a reload button. By default it clears the whole cache (an
/// image in memory is shown in the first render, without placeholder or transition) and builds
/// the content again, so the placeholder and the effects of the section play once more.
struct ImageSection<Content: View>: View {
    let title: String
    /// Whether reload clears the cache before rebuilding; `false` keeps it, to show the cache.
    var clearsCache = true
    @ViewBuilder let content: Content
    @State private var reloadID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Button(action: reload) {
                    Label("Reload", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 12) {
                content
            }
            .id(reloadID)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }

    private func reload() {
        guard clearsCache else {
            reloadID = UUID()
            return
        }
        Task { @Sendable in
            await HarborImage.clearCache()
            await MainActor.run { reloadID = UUID() }
        }
    }
}
