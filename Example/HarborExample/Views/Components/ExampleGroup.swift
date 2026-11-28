//
//  ExampleGroup.swift
//  HarborExample
//
//  Header and container for the feature sections of one area
//

import SwiftUI

/// A named area of the demo screen (REST, real time, security, ...) that stacks its feature
/// sections under a header with a one-line description.
struct ExampleGroup<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            content
        }
    }
}
