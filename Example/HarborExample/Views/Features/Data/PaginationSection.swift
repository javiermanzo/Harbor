//
//  PaginationSection.swift
//  HarborExample
//
//  A paginated GET.
//

import SwiftUI
import Harbor

struct PaginationSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    var body: some View {
        ExampleSection(title: "Pagination") {
            ExampleButton(title: "GET - Paginated", icon: "number") { performPaginatedRequest() }
        }
    }

    // MARK: - Actions

    private func performPaginatedRequest() {
        runner.log("=== GET - Paginated ===")
        runner.run {
            let response = await GetPaginatedPostsRequest(page: 1, limit: 5).request()

            await MainActor.run {
                switch response {
                case .success(let posts):
                    runner.log("Got \(posts.count) posts (page 1)")
                case .error(let error):
                    runner.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
