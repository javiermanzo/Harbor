//
//  FormatsSection.swift
//  HarborExample
//
//  SVG and animated GIF.
//

import SwiftUI
import HarborImage

struct FormatsSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    var body: some View {
        ImageSection(title: "Formats: SVG and animated GIF") {
            ImageCaptionGrid {
                ImageCaption("SVG") {
                    HImageView(url: ImageDemo.svgURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                    .downsampling(to: CGSize(width: 80, height: 80), contentMode: .fit)
                }

                ImageCaption("GIF, 1.5x") {
                    ImageGIF(.init(speed: 1.5)) { result in
                        runner.log("GIF: \(result.animation?.frameCount ?? 1) frames from \(result.source.rawValue)")
                    }
                }

                ImageCaption("GIF, one loop") {
                    ImageGIF(.init(loopCount: 1))
                }

                ImageCaption("GIF, paused") {
                    ImageGIF(.disabled)
                }
            }
        }
    }
}
