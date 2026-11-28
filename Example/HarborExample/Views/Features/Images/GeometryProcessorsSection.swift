//
//  GeometryProcessorsSection.swift
//  HarborExample
//
//  Processors that change the geometry: resize, crop, rotate, flip and padding.
//

import SwiftUI
import HarborImage

struct GeometryProcessorsSection: View {
    var body: some View {
        ImageSection(title: "Processors: geometry") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ImageProcessorTile("Resize fit", [])
                    ImageProcessorTile("Resize fill", [.resize(to: CGSize(width: 240, height: 160), mode: .fill)])
                    ImageProcessorTile("Crop", [.crop(size: CGSize(width: 120, height: 200), alignment: .topLeading)])
                    ImageProcessorTile("Rotate 15°", [.rotate(degrees: 15)])
                    ImageProcessorTile("Flip", [.flip(.horizontal)])
                    ImageProcessorTile("Padding", [.padding(HImageEdgeInsets(all: 24), color: .white)])
                }
            }
        }
    }
}
