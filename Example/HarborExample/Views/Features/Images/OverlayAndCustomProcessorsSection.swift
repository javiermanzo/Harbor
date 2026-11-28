//
//  OverlayAndCustomProcessorsSection.swift
//  HarborExample
//
//  The overlay processor, a custom `HImageProcessor` and a chain of processors.
//

import SwiftUI
import HarborImage

struct OverlayAndCustomProcessorsSection: View {
    var body: some View {
        ImageSection(title: "Processors: overlay and custom") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ImageProcessorTile("Overlay", [.overlay(ImageDemo.badge, id: "badge", alignment: .bottomTrailing, relativeWidth: 0.3, margin: 12)])
                    ImageProcessorTile("Custom (invert)", [InvertProcessor()])
                    ImageProcessorTile("Chained", [.grayscale, .roundedCorners(24), .overlay(ImageDemo.badge, id: "badge", alignment: .topLeading, relativeWidth: 0.25, margin: 10)])
                }
            }
        }
    }
}
