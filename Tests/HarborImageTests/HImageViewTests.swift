//
//  HImageViewTests.swift
//  HarborImageTests
//
//  HImageView rendered with ImageRenderer: the memory hot path (first render), placeholders,
//  the memory key of the modifiers, and the phase initializer with every modifier (callbacks
//  included) compiling together.
//

import SwiftUI
import XCTest
@testable import HarborCore
@testable import HarborImage

@MainActor
final class HImageViewTests: XCTestCase {

    override func setUp() async throws {
        await ImageTestDefaults.restore()
    }

    override func tearDown() async throws {
        await ImageTestDefaults.tearDown()
    }

    /// Renders a view at 20x20 points, scale 1.
    private func snapshot(_ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: 20, height: 20))
        renderer.scale = 1
        return renderer.cgImage
    }

    func testCachedImageIsShownInTheFirstRender() async throws {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png(width: 20, height: 20, color: .blue)))
        _ = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png")))

        // When
        let image = snapshot(HImageView(url: imageURL("/a.png")) { $0.resizable() } placeholder: { Color(red: 1, green: 0, blue: 0) })

        // Then
        let rendered = try XCTUnwrap(image)
        XCTAssertTrue(TestImages.pixel(rendered, x: 10, y: 10).isClose(to: .blue))
    }

    func testPlaceholderIsShownWhileNotCached() async throws {
        // When
        let image = snapshot(HImageView(url: imageURL("/not-loaded.png")) { $0.resizable() } placeholder: { Color(red: 1, green: 0, blue: 0) })

        // Then
        XCTAssertTrue(TestImages.pixel(try XCTUnwrap(image), x: 10, y: 10).isClose(to: .red))
    }

    func testModifiersChangeTheMemoryKey() async throws {
        // Given: only the processed variant is cached
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png(width: 20, height: 20, color: .blue)))
        _ = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png"), processors: [SolidColorProcessor(color: .green)]))

        // When
        let processed = snapshot(HImageView(url: imageURL("/a.png")) { $0.resizable() } placeholder: { Color(red: 1, green: 0, blue: 0) }
            .processors([SolidColorProcessor(color: .green)]))
        let plain = snapshot(HImageView(url: imageURL("/a.png")) { $0.resizable() } placeholder: { Color(red: 1, green: 0, blue: 0) })

        // Then
        XCTAssertTrue(TestImages.pixel(try XCTUnwrap(processed), x: 10, y: 10).isClose(to: .green))
        XCTAssertTrue(TestImages.pixel(try XCTUnwrap(plain), x: 10, y: 10).isClose(to: .red))
    }

    func testPhaseInitializerAndModifiersCompile() async throws {
        // When: every modifier chained, with a custom transition and callbacks
        let view = HImageView(request: HImageRequest(url: imageURL("/a.png"))) { phase in
            switch phase {
            case .empty(let progress): ProgressView(value: progress ?? 0)
            case .success(let image): image.resizable()
            case .failure(let error): Text(error.localizedDescription)
            }
        }
        .processors([.mask(.circle)])
        .encoding(.png)
        .cacheType(.memoryOnly)
        .cachePolicy(.useCache)
        .retryPolicy(HRetryPolicy(maxRetries: 1))
        .downsampling(to: CGSize(width: 20, height: 20))
        .transition(.custom(.scale.combined(with: .opacity), animation: .spring))
        .animatedPlayback(HAnimatedImagePlayback(loopCount: 1, speed: 2))
        .imageScale(2)
        .imageAccessibilityLabel(Text("Avatar"))
        .onSuccess { _ in }
        .onFailure { _ in }
        .onProgress { _ in }

        // Then
        XCTAssertNotNil(snapshot(view))
        XCTAssertNotNil(snapshot(HImageView(url: imageURL("/a.png"))))
    }

    func testPhaseAccessors() async {
        XCTAssertNil(HImagePhase.empty(progress: nil).image)
        XCTAssertNotNil(HImagePhase.success(Image(systemName: "star")).image)
        XCTAssertEqual(HImagePhase.failure(.notAnImage).error, .notAnImage)
    }
}
