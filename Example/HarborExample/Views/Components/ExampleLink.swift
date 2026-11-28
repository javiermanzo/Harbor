//
//  ExampleLink.swift
//  HarborExample
//
//  Row that opens a demo screen, styled like ExampleButton
//

import SwiftUI

struct ExampleLink<Destination: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 32)
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding()
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(12)
        }
    }
}
