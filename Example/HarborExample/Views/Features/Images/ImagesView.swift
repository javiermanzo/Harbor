//
//  ImagesView.swift
//  HarborExample
//
//  HarborImage, one section per feature: placeholders and phases, transitions, processors
//  (geometry, shape and color, custom shapes and masks, overlay and custom), formats (SVG,
//  animated GIF), downsampling with prefetching, cache policies and fallback, callbacks, direct
//  calls and compression. Every section with images has a reload button; the cache menu of the
//  navigation bar shows the disk cache size and clears the memory or the whole cache, reloading
//  every section.
//

import SwiftUI
import HarborImage

struct ImagesView: View {
    @StateObject private var runner = ExampleRunner()
    @State private var reloadAllID = UUID()
    /// Whether the mocks behind the failure demos are registered: the sections wait for it, so
    /// no image reaches the network before its mock exists.
    @State private var mocksReady = false

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if mocksReady {
                            imageSections
                        }

                        DirectCallsSection()
                    }
                    .padding()
                }

                ResultsConsoleView(results: runner.results) {
                    withAnimation { runner.clear() }
                }
            }
        }
        .environmentObject(runner)
        .navigationTitle("Images")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { cacheMenu }
        }
        .task {
            await registerMocks()
            mocksReady = true
        }
    }

    /// Every section with images, rebuilt together by the cache menu.
    private var imageSections: some View {
        Group {
            PlaceholderSection()
            TransitionsSection()
            GeometryProcessorsSection()
            ShapeAndColorProcessorsSection()
            CustomMaskSection()
            OverlayAndCustomProcessorsSection()
            FormatsSection()
            DownsamplingSection()
            CachePolicySection()
            CallbacksSection()
        }
        .id(reloadAllID)
    }

    // MARK: - Cache menu

    /// Always visible, so the effect of clearing the cache can be seen on any section.
    private var cacheMenu: some View {
        Menu {
            Button { showCacheSize() } label: { Label("Cache size", systemImage: "internaldrive") }
            Button { clearCache(.memory) } label: { Label("Clear memory and reload all", systemImage: "memorychip") }
            Button(role: .destructive) { clearCache(.all) } label: { Label("Clear cache and reload all", systemImage: "trash") }
        } label: {
            Image(systemName: "internaldrive")
        }
    }

    // MARK: - Actions

    /// Registers the mocked responses (debug builds only) behind the failure demos. In a release
    /// build the URLs reach the network and fail because the host does not exist.
    private func registerMocks() async {
        await HarborImage.register(HImageMock(url: ImageDemo.brokenURL, error: .api(statusCode: 404), delay: 1))
        await HarborImage.register(HImageMock(url: ImageDemo.movedURL, error: .api(statusCode: 404)))
    }

    /// Reads the disk cache size.
    private func showCacheSize() {
        Task { @Sendable in
            let size = await HarborImage.diskCacheSize()
            let count = await HarborImage.diskCacheCount()
            await MainActor.run { runner.log("Disk cache: \(count) files, \(size / 1024) KB") }
        }
    }

    /// Clears a cache layer (memory only: the images come back from disk) and reloads every section.
    private func clearCache(_ scope: HImageCache.Scope) {
        Task { @Sendable in
            await HarborImage.clearCache(scope)
            await MainActor.run {
                runner.log(scope == .memory ? "Memory cache cleared" : "Cache cleared")
                reloadAllID = UUID()
            }
        }
    }
}
