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
/// The values are owned by the presenting view (`HarborSettings`), so they survive the sheet being
/// dismissed and presented again and keep matching what was applied to Harbor.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var settings: HarborSettings

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Network")) {
                    Stepper("Timeout: \(Int(settings.timeoutInterval))s", value: $settings.timeoutInterval, in: 5...60)
                        .onChange(of: settings.timeoutInterval) { newValue in
                            Task { await Harbor.setDefaultTimeoutInterval(newValue) }
                        }

                    Picker("Cache Type", selection: $settings.cacheTypeIndex) {
                        Text(".urlCache").tag(0)
                        Text(".disabled").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: settings.cacheTypeIndex) { newValue in
                        Task {
                            let cacheType: HCache.CacheType = newValue == 0 ? .urlCache() : .disabled
                            await Harbor.setDefaultCacheType(cacheType)
                        }
                    }
                }

                Section(header: Text("Debug")) {
                    Toggle("Enable Logging", isOn: $settings.isLoggingEnabled)
                        .onChange(of: settings.isLoggingEnabled) { newValue in
                            Task { await Harbor.setLoggingEnabled(newValue) }
                        }
                }
            }
            .navigationTitle("Global Settings")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
}
