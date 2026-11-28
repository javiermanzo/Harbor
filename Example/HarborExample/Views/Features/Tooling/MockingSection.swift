//
//  MockingSection.swift
//  HarborExample
//
//  `HMock`: register responses and switch mocks on and off
//

import SwiftUI
import Harbor

struct MockingSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    @State private var isMocksEnabled = false

    var body: some View {
        ExampleSection(title: "Mocking") {
            Toggle(isOn: $isMocksEnabled) {
                HStack {
                    Image(systemName: "theatermasks")
                        .frame(width: 24)
                    Text("Enable Mocks")
                }
            }
            .padding()
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(12)
            .onChange(of: isMocksEnabled) { newValue in
                Task { await Harbor.setMocksEnabled(newValue) }
            }

            ExampleButton(title: "Register Mock Response", icon: "text.badge.plus") { registerMock() }
            ExampleButton(title: "Clear Mocks", icon: "trash", isDestructive: true) { clearMocks() }
        }
        .task {
            isMocksEnabled = await Harbor.mocksEnabled
        }
    }

    // MARK: - Actions

    private func registerMock() {
        let json = """
        [
          {
            "id": 999,
            "name": "Mocked User",
            "email": "mock@example.com"
          }
        ]
        """
        let mock = HMock(request: GetUsersRequest.self, statusCode: 200, jsonResponse: json, delay: 1.0)
        Task {
            await Harbor.register(mock: mock)
            await MainActor.run {
                runner.log("Registered mock for GetUsersRequest. With 'Enable Mocks' on, run 'GET - Simple Request' to get the mocked user.")
            }
        }
    }

    private func clearMocks() {
        Task {
            await Harbor.removeAllMocks()
            await MainActor.run {
                runner.log("All mocks removed")
            }
        }
    }
}
