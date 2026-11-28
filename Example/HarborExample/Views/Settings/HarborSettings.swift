//
//  HarborSettings.swift
//  HarborExample
//
//  Values shown in the settings sheet
//

import SwiftUI

/// Harbor's defaults, or what the settings sheet applied last. Owned by the home screen so the
/// values survive the sheet being dismissed and presented again.
@MainActor
final class HarborSettings: ObservableObject {
    @Published var timeoutInterval: Double = 15
    @Published var isLoggingEnabled = true
    /// 0: `.urlCache()`, 1: `.disabled`
    @Published var cacheTypeIndex = 0
}
