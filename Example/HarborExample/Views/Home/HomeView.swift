//
//  HomeView.swift
//  HarborExample
//
//  Home screen: an index of the areas of Harbor and the settings sheet
//

import SwiftUI

struct HomeView: View {
    @StateObject private var runner = ExampleRunner()
    @StateObject private var settings = HarborSettings()
    @State private var isSettingsPresented = false

    var body: some View {
        NavigationView {
            ExampleScreen(showsConsole: false) {
                ForEach(ExampleArea.allCases) { area in
                    ExampleAreaRow(area: area)
                }
            }
            .task { await ExampleSetup.configureOnce() }
            .navigationTitle("Harbor Examples")
            .navigationBarItems(trailing:
                Button(action: { isSettingsPresented = true }) {
                    Image(systemName: "gear")
                        .font(.system(size: 18, weight: .semibold))
                }
            )
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView(settings: settings)
            }
        }
        .environmentObject(runner)
        .overlay {
            if runner.isLoading {
                LoadingOverlay()
            }
        }
    }
}

#Preview {
    HomeView()
}
