//
//  RESTGroup.swift
//  HarborExample
//
//  The HTTP methods: GET, POST, PUT, PATCH and DELETE.
//

import SwiftUI

struct RESTGroup: View {
    var body: some View {
        ExampleGroup(title: "REST requests", subtitle: "One call per HTTP method.") {
            BasicRequestsSection()
            PostRequestsSection()
            PutPatchSection()
            DeleteSection()
        }
    }
}
