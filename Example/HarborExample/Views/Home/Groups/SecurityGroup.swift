//
//  SecurityGroup.swift
//  HarborExample
//
//  Screen of the "Security" area
//

import SwiftUI

struct SecurityGroup: View {
    private let area = ExampleArea.security

    var body: some View {
        ExampleScreen(subtitle: area.subtitle) {
            SecuritySection()
        }
        .navigationTitle(area.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
