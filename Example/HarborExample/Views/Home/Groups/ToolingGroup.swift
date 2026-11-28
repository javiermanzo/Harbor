//
//  ToolingGroup.swift
//  HarborExample
//
//  Mocking and debug logging.
//

import SwiftUI

struct ToolingGroup: View {
    var body: some View {
        ExampleGroup(title: "Testing and debugging", subtitle: "Mocks and request logging.") {
            MockingSection()
            DebugSection()
        }
    }
}
