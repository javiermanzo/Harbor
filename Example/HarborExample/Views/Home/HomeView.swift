//
//  HomeView.swift
//  HarborExample
//
//  Home screen: one group per area of Harbor, a sticky console and the settings sheet
//

import SwiftUI

struct HomeView: View {
    @StateObject private var runner = ExampleRunner()
    @StateObject private var settings = HarborSettings()
    @State private var isSettingsPresented = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 32) {
                            RESTGroup()
                            DataGroup()
                            ResilienceGroup()
                            RealtimeGroup()
                            MediaGroup()
                            SecurityGroup()
                            ToolingGroup()
                        }
                        .padding()
                    }

                    ResultsConsoleView(results: runner.results) {
                        withAnimation { runner.clear() }
                    }
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
