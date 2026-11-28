//
//  ExampleButton.swift
//  HarborExample
//
//  Button style used by the demo sections
//

import SwiftUI

struct ExampleButton: View {
    let title: String
    let icon: String
    var isDestructive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 32)
                    .foregroundColor(isDestructive ? .red : .accentColor)
                
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(Color.gray.opacity(0.5))
            }
            .padding()
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isDestructive ? Color.red.opacity(0.3) : Color.accentColor.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(SpringyButtonStyle())
    }
}

struct SpringyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
