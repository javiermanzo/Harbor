//
//  ResultsConsoleView.swift
//  HarborExample
//
//  Console-style output panel
//

import SwiftUI

/// Console-style output panel pinned to the bottom of the screen.
/// Shows example outputs and auto-scrolls to the newest entry.
struct ResultsConsoleView: View {
    let results: [String]
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Terminal Output")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                if !results.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.system(size: 16, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if results.isEmpty {
                            Text("> Ready")
                                .foregroundColor(.green)
                        } else {
                            ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(">")
                                        .foregroundColor(.green)
                                    Text(result)
                                        .foregroundColor(.white)
                                }
                                .id(index)
                            }
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .onChange(of: results.count) { _ in
                    if let lastIndex = results.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(height: 180)
            .background(Color(white: 0.1))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: -5)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(Color(UIColor.systemGroupedBackground))
    }
}
