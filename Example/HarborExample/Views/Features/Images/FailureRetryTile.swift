//
//  FailureRetryTile.swift
//  HarborExample
//
//  The failure phase with a retry button
//

import SwiftUI
import HarborImage

/// The failure phase with a retry button. The first load fails (a mocked 404 in debug builds);
/// the retry loads a URL that works, as a server that recovered would. The state lives here, so
/// reloading the section starts over with the failing URL.
struct FailureRetryTile: View {
    let failingURL: String
    let workingURL: String
    let onFailure: @MainActor (HImageError) -> Void
    @State private var hasRetried = false

    var body: some View {
        HImageView(request: HImageRequest(url: hasRetried ? workingURL : failingURL, cachePolicy: .reloadIgnoringCache)) { phase in
            switch phase {
            case .empty(let progress):
                ProgressView(value: progress ?? 0)
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Button { hasRetried = true } label: {
                    Image(systemName: "arrow.clockwise.circle.fill").font(.title)
                }
            }
        }
        .onFailure(onFailure)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
