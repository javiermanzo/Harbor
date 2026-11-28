//
//  ResilienceGroup.swift
//  HarborExample
//
//  Screen of the "Auth and resilience" area
//

import SwiftUI

struct ResilienceGroup: View {
    private let area = ExampleArea.resilience

    var body: some View {
        ExampleScreen(subtitle: area.subtitle) {
            AuthenticationSection()
            CustomHeadersSection()
            RetrySection()
        }
        .navigationTitle(area.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
