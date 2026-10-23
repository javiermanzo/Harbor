//
//  RequestsView+Mocking.swift
//  HarborExample
//
//  Mocking and debug requests
//

import SwiftUI
import Harbor

// MARK: - Mocking and debug requests
extension RequestsView {
    func registerMock() {
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
                addResult("Registered mock for GetUsersRequest. With 'Enable Mocks' on, run 'GET - Simple Request' to get the mocked user.")
            }
        }
    }

    // MARK: - Debug

    func performDebugRequest() {
        addResult("=== Debug Request ===")
        performWithLoading {
            let response = await DebugGetUsersRequest().request()

            await MainActor.run {
                switch response {
                case .success(let users):
                    addResult("Debug: Got \(users.count) users")
                case .error(let error):
                    addResult("Debug Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
