//
//  DataGroup.swift
//  HarborExample
//
//  Screen of the "Data" area
//

import SwiftUI

struct DataGroup: View {
    private let area = ExampleArea.data

    var body: some View {
        ExampleScreen(subtitle: area.subtitle) {
            CachingSection()
            StreamingSection()
            PaginationSection()
        }
        .navigationTitle(area.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
