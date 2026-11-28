//
//  TransitionsSection.swift
//  HarborExample
//
//  Appearance transitions: none, fade, scale, blur and custom.
//

import SwiftUI
import HarborImage

struct TransitionsSection: View {
    var body: some View {
        ImageSection(title: "Transitions") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ImageTransitionTile("None", .none)
                    ImageTransitionTile("Fade", .fade(duration: 0.8))
                    ImageTransitionTile("Scale", .scale(from: 0.5, duration: 0.6))
                    ImageTransitionTile("Blur", .blur(radius: 20, duration: 0.8))
                    ImageTransitionTile("Custom", .custom(.move(edge: .bottom).combined(with: .opacity),
                                                     animation: .spring(response: 0.5, dampingFraction: 0.6)))
                }
            }
        }
    }
}
