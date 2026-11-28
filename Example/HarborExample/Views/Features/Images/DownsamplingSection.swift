//
//  DownsamplingSection.swift
//  HarborExample
//
//  Photos decoded at their displayed size, and prefetched while the grid is on screen.
//

import SwiftUI
import HarborImage

struct DownsamplingSection: View {
    var body: some View {
        ImageSection(title: "Downsampling and prefetch") {
            // 600 px ImageDemo.photos decoded at 80 pt, and fetched ahead while the grid is on screen.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                ForEach(ImageDemo.photos, id: \.self) { url in
                    HImageView(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.15)
                    }
                    .downsampling(to: CGSize(width: 80, height: 80))
                    .frame(height: 80)
                    .clipped()
                }
            }
            .hImagePrefetch(ImageDemo.photos.map { HImageRequest(url: $0) })
        }
    }
}
