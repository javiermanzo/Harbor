//
//  CachePolicySection.swift
//  HarborExample
//
//  Fallback URLs and cache policies: where each image came from.
//

import SwiftUI
import HarborImage

struct CachePolicySection: View {
    @EnvironmentObject private var runner: ExampleRunner

    /// Where the last image of each tile came from, by tile title.
    @State private var sources: [String: HImageSource] = [:]
    /// Changed to rebuild the cache-only tile after its image was downloaded.
    @State private var cacheOnlyID = UUID()

    var body: some View {
        // Reload rebuilds the tiles without clearing the cache, so each policy shows its effect;
        // the caption says where the image came from. The cache menu clears it.
        ImageSection(title: "Cache policies and fallback", clearsCache: false) {
            ImageCaptionGrid {
                // The main URL fails with a non-retryable error and the fallback is loaded, then
                // cached under the main URL: from memory on reload.
                ImageCaption("Fallback URL", source: sources["Fallback URL"]) {
                    HImageView(request: HImageRequest(url: ImageDemo.movedURL, fallbackURLs: [ImageDemo.photos[5]])) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .onSuccess { sources["Fallback URL"] = $0.source }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // `.returnCacheDontLoad` never goes to the network: it shows only what the cache
                // holds and fails with `.notCached` otherwise. The button downloads the image (which
                // stores it) and rebuilds the tile, which then finds it in the cache. After "Clear
                // cache" in the menu, it is "Not cached" again.
                ImageCaption("Cache only", source: sources["Cache only"]) {
                    HImageView(request: HImageRequest(url: ImageDemo.cacheOnlyURL, cachePolicy: .returnCacheDontLoad)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure(.notCached):
                            Button(action: downloadForCacheOnly) {
                                VStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle.fill").font(.title2)
                                    Text("Not cached").font(.caption2)
                                }
                            }
                        case .failure:
                            Text("Error").font(.caption2)
                        case .empty:
                            Color.gray.opacity(0.2)
                        }
                    }
                    .onSuccess { sources["Cache only"] = $0.source }
                    .id(cacheOnlyID)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Decoded in memory only, never written to disk: downloaded the first time, from
                // memory on reload, downloaded again after "Clear memory" or an app relaunch.
                ImageCaption("Memory only", source: sources["Memory only"]) {
                    HImageView(url: ImageDemo.photos[6]) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .cacheType(.memoryOnly)
                    .onSuccess { sources["Memory only"] = $0.source }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // `.reloadIgnoringCache`: downloaded on every load, then cached for the others.
                ImageCaption("Always reload", source: sources["Always reload"]) {
                    HImageView(url: ImageDemo.photos[8]) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .cachePolicy(.reloadIgnoringCache)
                    .onSuccess { sources["Always reload"] = $0.source }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Actions

    /// Downloads the cache-only image with the default policy, which stores it, then rebuilds the
    /// cache-only tile so it reads it from the cache.
    private func downloadForCacheOnly() {
        let request = HImageRequest(url: ImageDemo.cacheOnlyURL)
        Task { @Sendable in
            let response = await HarborImage.image(for: request)
            await MainActor.run {
                runner.log(response.error.map { "Download failed: \($0.localizedDescription)" } ?? "Downloaded and cached: the cache-only tile reads it now")
                cacheOnlyID = UUID()
            }
        }
    }
}
