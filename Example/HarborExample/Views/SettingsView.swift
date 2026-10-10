//
//  SettingsView.swift
//  HarborExample
//
//  Global Harbor settings sheet
//

import SwiftUI
import Harbor

/// Interactive configuration panel for Harbor settings.
///
/// The values are owned by the presenting view (bindings), so they survive the sheet being
/// dismissed and presented again and keep matching what was applied to Harbor.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var timeoutInterval: Double
    @Binding var isLoggingEnabled: Bool
    /// 0: `.urlCache()`, 1: `.disabled`
    @Binding var cacheTypeIndex: Int

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Network")) {
                    Stepper("Timeout: \(Int(timeoutInterval))s", value: $timeoutInterval, in: 5...60)
                        .onChange(of: timeoutInterval) { newValue in
                            Task { await Harbor.setDefaultTimeoutInterval(newValue) }
                        }

                    Picker("Cache Type", selection: $cacheTypeIndex) {
                        Text(".urlCache").tag(0)
                        Text(".disabled").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: cacheTypeIndex) { newValue in
                        Task {
                            let cacheType: HCache.CacheType = newValue == 0 ? .urlCache() : .disabled
                            await Harbor.setDefaultCacheType(cacheType)
                        }
                    }
                }

                Section(header: Text("Debug")) {
                    Toggle("Enable Logging", isOn: $isLoggingEnabled)
                        .onChange(of: isLoggingEnabled) { newValue in
                            Task { await Harbor.setLoggingEnabled(newValue) }
                        }
                }
            }
            .navigationTitle("Global Settings")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
}
