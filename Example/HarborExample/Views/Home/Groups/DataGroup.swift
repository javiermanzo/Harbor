//
//  DataGroup.swift
//  HarborExample
//
//  Caching, streaming and pagination.
//

import SwiftUI

struct DataGroup: View {
    var body: some View {
        ExampleGroup(title: "Data", subtitle: "Caching, streaming and pagination.") {
            CachingSection()
            StreamingSection()
            PaginationSection()
        }
    }
}
