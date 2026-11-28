//
//  ShapeAndColorProcessorsSection.swift
//  HarborExample
//
//  Processors for shape and color: masks, border, rounded corners, grayscale, tint, blur.
//

import SwiftUI
import HarborImage

struct ShapeAndColorProcessorsSection: View {
    var body: some View {
        ImageSection(title: "Processors: shape and color") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ImageProcessorTile("Circle + border", [.mask(.circle), .border(width: 8, color: .white, shape: .circle)])
                    ImageProcessorTile("Capsule", [.mask(.capsule)])
                    ImageProcessorTile("Rounded", [.roundedCorners(32)])
                    ImageProcessorTile("Grayscale", [.grayscale])
                    ImageProcessorTile("Adjust", [.adjust(brightness: 0.1, contrast: 1.3, saturation: 1.6)])
                    ImageProcessorTile("Tint", [.tint(HImageColor(red: 0.2, green: 0.4, blue: 1, alpha: 0.6))])
                    ImageProcessorTile("Blur", [.blur(radius: 6)])
                }
            }
        }
    }
}
