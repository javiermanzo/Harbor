//
//  CallbacksSection.swift
//  HarborExample
//
//  `HImageView` callbacks: `.onProgress`, `.onSuccess` and `.onFailure`.
//

import SwiftUI
import HarborImage

struct CallbacksSection: View {
    @State private var callbackProgress: Double?
    @State private var callbackStatus = "Waiting"

    var body: some View {
        ImageSection(title: "View callbacks") {
            HImageView(request: HImageRequest(url: "https://picsum.photos/id/237/1600/1200", cachePolicy: .reloadIgnoringCache)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .onProgress { callbackProgress = $0 }
            .onSuccess { result in
                callbackProgress = nil
                callbackStatus = "\(result.image.width)x\(result.image.height) from \(result.source.rawValue)"
            }
            .onFailure { error in
                callbackProgress = nil
                callbackStatus = error.localizedDescription
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let callbackProgress {
                ProgressView(value: callbackProgress)
            }
            Text(".onProgress / .onSuccess / .onFailure: \(callbackStatus)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
