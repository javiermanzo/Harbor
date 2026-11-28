//
//  RESTGroup.swift
//  HarborExample
//
//  Screen of the "REST requests" area
//

import SwiftUI

struct RESTGroup: View {
    private let area = ExampleArea.rest

    var body: some View {
        ExampleScreen(subtitle: area.subtitle) {
            BasicRequestsSection()
            PostRequestsSection()
            PutPatchSection()
            DeleteSection()
        }
        .navigationTitle(area.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
