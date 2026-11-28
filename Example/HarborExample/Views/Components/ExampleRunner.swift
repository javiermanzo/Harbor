//
//  ExampleRunner.swift
//  HarborExample
//
//  Shared output and loading state of the demo screens
//

import SwiftUI

/// The console output and the loading flag shared by every demo section of a screen.
///
/// A screen owns one runner (`@StateObject`) and injects it with `.environmentObject`, so each
/// feature section logs and runs its requests without the screen passing state down by hand.
@MainActor
final class ExampleRunner: ObservableObject {
    @Published private(set) var results: [String] = []
    @Published private(set) var isLoading = false

    /// Appends a line to the console.
    func log(_ text: String) {
        results.append(text)
    }

    func clear() {
        results.removeAll()
    }

    /// Runs an async operation while the loading overlay is shown.
    func run(_ operation: @escaping @MainActor () async -> Void) {
        isLoading = true
        Task {
            await operation()
            isLoading = false
        }
    }
}
