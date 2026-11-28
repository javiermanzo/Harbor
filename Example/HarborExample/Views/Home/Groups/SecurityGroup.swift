//
//  SecurityGroup.swift
//  HarborExample
//
//  mTLS and SSL pinning.
//

import SwiftUI

struct SecurityGroup: View {
    var body: some View {
        ExampleGroup(title: "Security", subtitle: "Client certificates and certificate pinning.") {
            SecuritySection()
        }
    }
}
