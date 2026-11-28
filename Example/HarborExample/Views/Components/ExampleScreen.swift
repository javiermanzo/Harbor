//
//  ExampleScreen.swift
//  HarborExample
//
//  Scrolling content with the sticky console below it
//

import SwiftUI

/// The frame of every demo screen: grouped background, the content in a scroll view and, unless
/// `showsConsole` is `false` (screens that only navigate), the console of the environment's
/// `ExampleRunner` pinned to the bottom.
struct ExampleScreen<Content: View>: View {
    @EnvironmentObject private var runner: ExampleRunner

    var subtitle: String?
    var showsConsole = true
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                        }
                        content
                    }
                    .padding()
                }

                if showsConsole {
                    ResultsConsoleView(results: runner.results) {
                        withAnimation { runner.clear() }
                    }
                }
            }
        }
    }
}
