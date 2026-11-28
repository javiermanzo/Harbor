//
//  ResilienceGroup.swift
//  HarborExample
//
//  Authentication, custom headers and retries.
//

import SwiftUI

struct ResilienceGroup: View {
    var body: some View {
        ExampleGroup(title: "Auth and resilience", subtitle: "Authentication, headers and retries.") {
            AuthenticationSection()
            CustomHeadersSection()
            RetrySection()
        }
    }
}
