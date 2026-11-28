//
//  CustomMaskSection.swift
//  HarborExample
//
//  Masks with a custom path (unit coordinates, origin at the top left) and with the alpha of
//  another image, and a border that follows the custom path.
//

import SwiftUI
import HarborImage

struct CustomMaskSection: View {
    var body: some View {
        ImageSection(title: "Processors: custom shapes and masks") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ImageProcessorTile("Ellipse", [.mask(.ellipse)])
                    ImageProcessorTile("Star path", [.mask(.path(ImageDemo.starPath, id: "star"))])
                    ImageProcessorTile("Star + border", [.mask(.path(ImageDemo.starPath, id: "star")),
                                           .border(width: 10, color: .white, shape: .path(ImageDemo.starPath, id: "star"))])
                    ImageProcessorTile("Heart path", [.mask(.path(ImageDemo.heartPath, id: "heart"))])
                    ImageProcessorTile("Image mask", [.mask(.image(ImageDemo.vignetteMask, id: "vignette"))])
                }
            }
        }
    }
}
