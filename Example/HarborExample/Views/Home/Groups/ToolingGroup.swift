//
//  ToolingGroup.swift
//  HarborExample
//
//  Screen of the "Testing and debugging" area
//

import SwiftUI

struct ToolingGroup: View {
    private let area = ExampleArea.tooling

    var body: some View {
        ExampleScreen(subtitle: area.subtitle) {
            MockingSection()
            DebugSection()
        }
        .navigationTitle(area.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
