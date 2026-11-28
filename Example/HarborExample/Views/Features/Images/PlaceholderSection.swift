//
//  PlaceholderSection.swift
//  HarborExample
//
//  Placeholder view, per-phase content, failure and retry.
//

import SwiftUI
import HarborImage

struct PlaceholderSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    var body: some View {
        ImageSection(title: "Placeholder and phases") {
            ImageCaptionGrid {
                ImageCaption("Placeholder view") {
                    HImageView(url: ImageDemo.photos[0]) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .cachePolicy(.reloadIgnoringCache)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                ImageCaption("Color placeholder") {
                    HImageView(url: ImageDemo.photos[1]) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        LinearGradient(colors: [.gray.opacity(0.2), .gray.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                    }
                    .cachePolicy(.reloadIgnoringCache)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                ImageCaption("Phase + progress") {
                    HImageView(url: ImageDemo.photos[2]) { phase in
                        switch phase {
                        case .empty(let progress): ProgressView(value: progress ?? 0)
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure(let error): Text(error.localizedDescription).font(.caption2)
                        }
                    }
                    .cachePolicy(.reloadIgnoringCache)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                ImageCaption("Failure + retry") {
                    FailureRetryTile(failingURL: ImageDemo.brokenURL, workingURL: ImageDemo.photos[3]) { error in
                        runner.log("Failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
