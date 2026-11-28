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
import CoreImage
import HarborImage

struct ImagesView: View {
    @State private var results: [String] = []
    @State private var reloadAllID = UUID()
    @State private var directImage: CGImage?
    @State private var directProgress: Double?
    @State private var directTask: Task<Void, Never>?
    /// Where the last image of each cache policy tile came from, by tile title.
    @State private var sources: [String: HImageSource] = [:]
    @State private var callbackProgress: Double?
    @State private var callbackStatus = "Waiting"
    /// Whether the mocks behind the failure demos are registered: the sections wait for it, so
    /// no image reaches the network before its mock exists.
    @State private var mocksReady = false
    /// Changed to rebuild the cache-only tile after its image was downloaded.
    @State private var cacheOnlyID = UUID()

    /// Photos from picsum.photos (stable ids, any size).
    private let photos = (10..<40).map { "https://picsum.photos/id/\($0)/600/600" }
    /// Answered by a mock (debug builds), so the failure is the same every time.
    private let brokenURL = "https://images.example.com/missing.png"
    /// The failing main URL of the fallback demo, answered by its own mock (debug builds); the
    /// fallback image is cached under it.
    private let movedURL = "https://images.example.com/moved.png"
    /// A small SVG inlined as a `data:` URL, so it works offline.
    private let svgURL = "data:image/svg+xml;utf8," + (#"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">\#
    <stop offset="0" stop-color="#4f8cff"/><stop offset="1" stop-color="#a64fff"/></linearGradient></defs>\#
    <circle cx="12" cy="12" r="11" fill="url(#g)"/><path d="M7 12.5l3 3 7-7" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
    """#.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
    /// Only loaded by the cache-only demo, so nothing else puts it in the cache.
    private let cacheOnlyURL = "https://picsum.photos/id/1015/600/600"
    /// An animated GIF.
    private let gifURL = "https://upload.wikimedia.org/wikipedia/commons/2/2c/Rotating_earth_%28large%29.gif"

    private let square = CGSize(width: 240, height: 240)

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if mocksReady {
                            sections
                        }

                        directCallsSection
                    }
                    .padding()
                }

                ResultsConsoleView(results: results) {
                    withAnimation { results.removeAll() }
                }
            }
        }
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
    private var sections: some View {
        Group {
            placeholderSection
            transitionsSection
            geometrySection
            shapeAndColorSection
            customMaskSection
            overlayAndCustomSection
            formatsSection
            downsamplingSection
            cachePolicySection
            callbacksSection
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

    // MARK: - Sections

    /// `HImageView` shows a placeholder while the image loads (and when it fails) with the
    /// `content` + `placeholder` initializer, or one view per phase with the `phase` initializer.
    private var placeholderSection: some View {
        ImageSection(title: "Placeholder and phases") {
            captionGrid {
                caption("Placeholder view") {
                    HImageView(url: photos[0]) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .cachePolicy(.reloadIgnoringCache)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                caption("Color placeholder") {
                    HImageView(url: photos[1]) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        LinearGradient(colors: [.gray.opacity(0.2), .gray.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                    }
                    .cachePolicy(.reloadIgnoringCache)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                caption("Phase + progress") {
                    HImageView(url: photos[2]) { phase in
                        switch phase {
                        case .empty(let progress): ProgressView(value: progress ?? 0)
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure(let error): Text(error.localizedDescription).font(.caption2)
                        }
                    }
                    .cachePolicy(.reloadIgnoringCache)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                caption("Failure + retry") {
                    FailureRetryTile(failingURL: brokenURL, workingURL: photos[3]) { error in
                        log("Failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private var transitionsSection: some View {
        ImageSection(title: "Transitions") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    transitionTile("None", .none)
                    transitionTile("Fade", .fade(duration: 0.8))
                    transitionTile("Scale", .scale(from: 0.5, duration: 0.6))
                    transitionTile("Blur", .blur(radius: 20, duration: 0.8))
                    transitionTile("Custom", .custom(.move(edge: .bottom).combined(with: .opacity),
                                                     animation: .spring(response: 0.5, dampingFraction: 0.6)))
                }
            }
        }
    }

    private var geometrySection: some View {
        ImageSection(title: "Processors: geometry") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    tile("Resize fit", [])
                    tile("Resize fill", [.resize(to: CGSize(width: 240, height: 160), mode: .fill)])
                    tile("Crop", [.crop(size: CGSize(width: 120, height: 200), alignment: .topLeading)])
                    tile("Rotate 15°", [.rotate(degrees: 15)])
                    tile("Flip", [.flip(.horizontal)])
                    tile("Padding", [.padding(HImageEdgeInsets(all: 24), color: .white)])
                }
            }
        }
    }

    private var shapeAndColorSection: some View {
        ImageSection(title: "Processors: shape and color") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    tile("Circle + border", [.mask(.circle), .border(width: 8, color: .white, shape: .circle)])
                    tile("Capsule", [.mask(.capsule)])
                    tile("Rounded", [.roundedCorners(32)])
                    tile("Grayscale", [.grayscale])
                    tile("Adjust", [.adjust(brightness: 0.1, contrast: 1.3, saturation: 1.6)])
                    tile("Tint", [.tint(HImageColor(red: 0.2, green: 0.4, blue: 1, alpha: 0.6))])
                    tile("Blur", [.blur(radius: 6)])
                }
            }
        }
    }

    /// Masks with a custom path (unit coordinates, origin at the top left) and with the alpha of
    /// another image, and a border that follows the custom path.
    private var customMaskSection: some View {
        ImageSection(title: "Processors: custom shapes and masks") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    tile("Ellipse", [.mask(.ellipse)])
                    tile("Star path", [.mask(.path(Self.starPath, id: "star"))])
                    tile("Star + border", [.mask(.path(Self.starPath, id: "star")),
                                           .border(width: 10, color: .white, shape: .path(Self.starPath, id: "star"))])
                    tile("Heart path", [.mask(.path(Self.heartPath, id: "heart"))])
                    tile("Image mask", [.mask(.image(Self.vignetteMask, id: "vignette"))])
                }
            }
        }
    }

    private var overlayAndCustomSection: some View {
        ImageSection(title: "Processors: overlay and custom") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    tile("Overlay", [.overlay(Self.badge, id: "badge", alignment: .bottomTrailing, relativeWidth: 0.3, margin: 12)])
                    tile("Custom (invert)", [InvertProcessor()])
                    tile("Chained", [.grayscale, .roundedCorners(24), .overlay(Self.badge, id: "badge", alignment: .topLeading, relativeWidth: 0.25, margin: 10)])
                }
            }
        }
    }

    private var formatsSection: some View {
        ImageSection(title: "Formats: SVG and animated GIF") {
            captionGrid {
                caption("SVG") {
                    HImageView(url: svgURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                    .downsampling(to: CGSize(width: 80, height: 80), contentMode: .fit)
                }

                caption("GIF, 1.5x") {
                    gif(.init(speed: 1.5)) { result in
                        log("GIF: \(result.animation?.frameCount ?? 1) frames from \(result.source.rawValue)")
                    }
                }

                caption("GIF, one loop") {
                    gif(.init(loopCount: 1))
                }

                caption("GIF, paused") {
                    gif(.disabled)
                }
            }
        }
    }

    private var downsamplingSection: some View {
        ImageSection(title: "Downsampling and prefetch") {
            // 600 px photos decoded at 80 pt, and fetched ahead while the grid is on screen.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                ForEach(photos, id: \.self) { url in
                    HImageView(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.15)
                    }
                    .downsampling(to: CGSize(width: 80, height: 80))
                    .frame(height: 80)
                    .clipped()
                }
            }
            .hImagePrefetch(photos.map { HImageRequest(url: $0) })
        }
    }

    private var cachePolicySection: some View {
        // Reload rebuilds the tiles without clearing the cache, so each policy shows its effect;
        // the caption says where the image came from. The cache menu clears it.
        ImageSection(title: "Cache policies and fallback", clearsCache: false) {
            captionGrid {
                // The main URL fails with a non-retryable error and the fallback is loaded, then
                // cached under the main URL: from memory on reload.
                caption("Fallback URL", source: sources["Fallback URL"]) {
                    HImageView(request: HImageRequest(url: movedURL, fallbackURLs: [photos[5]])) { image in
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
                caption("Cache only", source: sources["Cache only"]) {
                    HImageView(request: HImageRequest(url: cacheOnlyURL, cachePolicy: .returnCacheDontLoad)) { phase in
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
                caption("Memory only", source: sources["Memory only"]) {
                    HImageView(url: photos[6]) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .cacheType(.memoryOnly)
                    .onSuccess { sources["Memory only"] = $0.source }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // `.reloadIgnoringCache`: downloaded on every load, then cached for the others.
                caption("Always reload", source: sources["Always reload"]) {
                    HImageView(url: photos[8]) { image in
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

    private var callbacksSection: some View {
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

    private var directCallsSection: some View {
        ExampleSection(title: "Direct calls (no view)") {
            if let directImage {
                Image(decorative: directImage, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
            }
            if let directProgress {
                ProgressView(value: directProgress)
            }
            ExampleButton(title: "Load with progress callback", icon: "arrow.down.circle") { loadWithCallbacks() }
            ExampleButton(title: "Cancel load", icon: "xmark.circle", isDestructive: true) {
                directTask?.cancel()
            }
            ExampleButton(title: "Events as an AsyncStream", icon: "dot.radiowaves.left.and.right") { streamEvents() }
            ExampleButton(title: "Original bytes (data)", icon: "doc.zipper") { loadOriginalBytes() }
            ExampleButton(title: "async + compress to 50 KB", icon: "arrow.down.right.and.arrow.up.left") { loadAndCompress() }
        }
    }

    // MARK: - Layout helpers

    /// Four demo slots per row that share the width of the section, so a section is never wider
    /// than the screen.
    private func captionGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 4), spacing: 16) {
            content()
        }
    }

    /// A square demo slot (at most 80 pt) with a caption below it and, when known, where its
    /// image came from.
    private func caption<Content: View>(_ title: String, source: HImageSource? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 80)
                .overlay(content())
                .clipped()
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if let source {
                Text("from \(source.rawValue)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.accentColor)
            }
        }
    }

    /// The same photo with a list of processors, shown 96 pt wide.
    private func tile(_ title: String, _ processors: [any HImageProcessor]) -> some View {
        VStack(spacing: 6) {
            HImageView(url: photos[7]) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView()
            }
            .processors([.resize(to: square, mode: .fit)] + processors)
            .frame(width: 96, height: 96)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    /// A photo that always loads again, so its transition plays on every reload.
    private func transitionTile(_ title: String, _ transition: HImageTransition) -> some View {
        VStack(spacing: 6) {
            HImageView(url: photos[9]) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .cachePolicy(.reloadIgnoringCache)
            .transition(transition)
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func gif(_ playback: HAnimatedImagePlayback,
                     onSuccess: @escaping @MainActor (HImageResult) -> Void = { _ in }) -> some View {
        HImageView(url: gifURL) { phase in
            switch phase {
            case .empty(let progress): ProgressView(value: progress ?? 0)
            case .success(let image): image.resizable().scaledToFit()
            case .failure(let error): Text(error.localizedDescription).font(.caption2)
            }
        }
        .downsampling(to: CGSize(width: 80, height: 80), contentMode: .fit)
        .animatedPlayback(playback)
        .onSuccess(onSuccess)
    }

    private func log(_ text: String) {
        results.append(text)
    }

    /// A small badge drawn in code, used by the overlay processor.
    private static let badge: CGImage = {
        let size = CGSize(width: 120, height: 120)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemOrange.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            UIColor.white.setStroke()
            context.cgContext.setLineWidth(10)
            context.cgContext.strokeEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5))
        }
        return image.cgImage!
    }()

    /// A five-pointed star in unit coordinates (`0...1`, origin at the top left), the coordinate
    /// space of `HImageMaskShape.path(_:id:)`.
    private static let starPath: CGPath = {
        let path = CGMutablePath()
        let center = CGPoint(x: 0.5, y: 0.52)
        for index in 0..<10 {
            let radius = index.isMultiple(of: 2) ? 0.5 : 0.21
            let angle = Double(index) * .pi / 5 - .pi / 2
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }()

    /// A heart in unit coordinates, drawn with Bézier curves.
    private static let heartPath: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.5, y: 0.92))
        path.addCurve(to: CGPoint(x: 0.04, y: 0.34), control1: CGPoint(x: 0.2, y: 0.7), control2: CGPoint(x: 0.04, y: 0.55))
        path.addCurve(to: CGPoint(x: 0.5, y: 0.2), control1: CGPoint(x: 0.04, y: 0.05), control2: CGPoint(x: 0.4, y: 0.02))
        path.addCurve(to: CGPoint(x: 0.96, y: 0.34), control1: CGPoint(x: 0.6, y: 0.02), control2: CGPoint(x: 0.96, y: 0.05))
        path.addCurve(to: CGPoint(x: 0.5, y: 0.92), control1: CGPoint(x: 0.96, y: 0.55), control2: CGPoint(x: 0.8, y: 0.7))
        path.closeSubpath()
        return path
    }()

    /// A mask image whose alpha fades from opaque in the center to transparent at the edges:
    /// `HImageMaskShape.image(_:id:)` keeps the photo where the mask is opaque.
    private static let vignetteMask: CGImage = {
        let size = CGSize(width: 120, height: 120)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.35, 1])!
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width / 2, options: [])
        }
        return image.cgImage!
    }()

    // MARK: - Actions

    /// Downloads the cache-only image with the default policy, which stores it, then rebuilds the
    /// cache-only tile so it reads it from the cache.
    private func downloadForCacheOnly() {
        let request = HImageRequest(url: cacheOnlyURL)
        Task { @Sendable in
            let response = await HarborImage.image(for: request)
            await MainActor.run {
                log(response.error.map { "Download failed: \($0.localizedDescription)" } ?? "Downloaded and cached: the cache-only tile reads it now")
                cacheOnlyID = UUID()
            }
        }
    }

    /// Registers the mocked responses (debug builds only) behind the failure demos. In a release
    /// build the URLs reach the network and fail because the host does not exist.
    private func registerMocks() async {
        await HarborImage.register(HImageMock(url: brokenURL, error: .api(statusCode: 404), delay: 1))
        await HarborImage.register(HImageMock(url: movedURL, error: .api(statusCode: 404)))
    }

    /// `HarborImage.image(for:onEvent:)` with the optional progress callback (main actor).
    /// Cancelling the task cancels the load.
    private func loadWithCallbacks() {
        directImage = nil
        directProgress = 0
        let request = HImageRequest(url: "https://picsum.photos/id/\(Int.random(in: 50...200))/1600/1200",
                                    cachePolicy: .reloadIgnoringCache)
        directTask = Task { @Sendable in
            let response = await HarborImage.image(for: request, onEvent: { event in
                if case .progress(let fraction) = event { directProgress = fraction }
            })
            await MainActor.run {
                directProgress = nil
                switch response {
                case .success(let result):
                    directImage = result.image
                    log("image: \(result.image.width)x\(result.image.height) from \(result.source.rawValue)")
                case .failure(let error):
                    log("image failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// `HarborImage.events(for:)`: the same events as the callback, as an `AsyncStream`.
    private func streamEvents() {
        let request = HImageRequest(url: "https://picsum.photos/id/\(Int.random(in: 200...300))/800/600",
                                    cachePolicy: .reloadIgnoringCache)
        Task { @Sendable in
            for await event in HarborImage.events(for: request) {
                let line: String
                switch event {
                case .started: line = "event: started"
                case .progress(let fraction): line = "event: progress \(Int(fraction * 100))%"
                case .retrying(let attempt): line = "event: retrying (\(attempt))"
                case .loaded(let source): line = "event: loaded from \(source.rawValue)"
                case .finished(let response): line = "event: finished (\(response.error == nil ? "success" : "failure"))"
                }
                await MainActor.run { log(line) }
            }
        }
    }

    /// `HarborImage.data(for:)`: the original bytes, neither decoded nor processed.
    private func loadOriginalBytes() {
        let request = HImageRequest(url: photos[4])
        Task { @Sendable in
            let message: String
            switch await HarborImage.data(for: request) {
            case .success(let data, let format, let source):
                message = "data: \(data.count / 1024) KB \(format.rawValue) from \(source.rawValue)"
            case .failure(let error):
                message = "data failed: \(error.localizedDescription)"
            }
            await MainActor.run { log(message) }
        }
    }

    /// `HarborImage.image(for:)` with async/await, then compression without downloading again.
    private func loadAndCompress() {
        let url = photos[3]
        Task { @Sendable in
            let response = await HarborImage.image(for: HImageRequest(url: url))
            guard let image = response.result?.image else {
                await MainActor.run { log("image failed: \(response.error?.localizedDescription ?? "")") }
                return
            }
            let message: String
            do {
                let data = try await HarborImage.encode(image, as: .jpeg(quality: 0.9, maxBytes: 50_000))
                message = "JPEG under 50 KB: \(data.count) bytes"
            } catch {
                message = "encode failed: \(error.localizedDescription)"
            }
            await MainActor.run { log(message) }
        }
    }

    /// Reads the disk cache size.
    private func showCacheSize() {
        Task { @Sendable in
            let size = await HarborImage.diskCacheSize()
            let count = await HarborImage.diskCacheCount()
            await MainActor.run { log("Disk cache: \(count) files, \(size / 1024) KB") }
        }
    }

    /// Clears a cache layer (memory only: the images come back from disk) and reloads every section.
    private func clearCache(_ scope: HImageCache.Scope) {
        Task { @Sendable in
            await HarborImage.clearCache(scope)
            await MainActor.run {
                log(scope == .memory ? "Memory cache cleared" : "Cache cleared")
                reloadAllID = UUID()
            }
        }
    }
}

// MARK: - ImageSection

/// A section card whose header has a reload button. By default it clears the whole cache (an
/// image in memory is shown in the first render, without placeholder or transition) and builds
/// the content again, so the placeholder and the effects of the section play once more.
private struct ImageSection<Content: View>: View {
    let title: String
    /// Whether reload clears the cache before rebuilding; `false` keeps it, to show the cache.
    var clearsCache = true
    @ViewBuilder let content: Content
    @State private var reloadID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Button(action: reload) {
                    Label("Reload", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 12) {
                content
            }
            .id(reloadID)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }

    private func reload() {
        guard clearsCache else {
            reloadID = UUID()
            return
        }
        Task { @Sendable in
            await HarborImage.clearCache()
            await MainActor.run { reloadID = UUID() }
        }
    }
}

// MARK: - FailureRetryTile

/// The failure phase with a retry button. The first load fails (a mocked 404 in debug builds);
/// the retry loads a URL that works, as a server that recovered would. The state lives here, so
/// reloading the section starts over with the failing URL.
private struct FailureRetryTile: View {
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

// MARK: - Custom processor

/// A custom `HImageProcessor`: inverts the colors with Core Image. The identifier is part of the
/// cache key, so it is stable and includes every parameter (there are none here).
private struct InvertProcessor: HImageProcessor {
    var identifier: String { "invert" }

    func process(_ image: CGImage, context: HImageProcessingContext) async throws -> CGImage {
        let input = CIImage(cgImage: image)
        guard let output = CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: input])?.outputImage,
              let result = CIContext().createCGImage(output, from: input.extent) else {
            throw HImageError.processingFailed("invert: Core Image failed")
        }
        return result
    }
}
