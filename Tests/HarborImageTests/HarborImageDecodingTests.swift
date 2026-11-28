//
//  HarborImageDecodingTests.swift
//  HarborImageTests
//
//  Format detection, downsampling, EXIF orientation, files with several images, animated
//  images, custom decoders, SVG rasterization and corrupted data.
//

import ImageIO
import XCTest
@testable import HarborCore
@testable import HarborImage

@HRequestManagerActor
final class HarborImageDecodingTests: XCTestCase {

    override func setUp() async throws {
        await ImageTestDefaults.restore()
    }

    override func tearDown() async throws {
        await ImageTestDefaults.tearDown()
    }

    func testFormatDetectionUsesTheBytes() async {
        // Then
        XCTAssertEqual(HImageFormat.detect(TestImages.png()), .png)
        XCTAssertEqual(HImageFormat.detect(TestImages.jpeg()), .jpeg)
        XCTAssertEqual(HImageFormat.detect(TestImages.gif(colors: [.red])), .gif)
        XCTAssertEqual(HImageFormat.detect(Data("RIFF\0\0\0\0WEBPVP8 ".utf8)), .webp)
        XCTAssertEqual(HImageFormat.detect(Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)), .svg)
        XCTAssertNil(HImageFormat.detect(Data("<html><body></body></html>".utf8)))
        XCTAssertNil(HImageFormat.detect(Data()))
    }

    func testTargetSizeDownsamplesWhileDecoding() async throws {
        // Given
        ImageStubProtocol.stub("/big.jpg", ImageStubResponse(body: TestImages.jpeg(width: 400, height: 200)))
        let request = HImageRequest(url: imageURL("/big.jpg"), targetSize: HImageTargetSize(pixelWidth: 100, pixelHeight: 100, contentMode: .fit))

        // When
        let resultLoaded = await HarborImage.image(for: request).result
        let result = try XCTUnwrap(resultLoaded)

        // Then
        XCTAssertEqual(result.pixelSize, CGSize(width: 100, height: 50))
    }

    func testLeadingResizeProcessorProducesItsSize() async throws {
        // Given
        ImageStubProtocol.stub("/big.jpg", ImageStubResponse(body: TestImages.jpeg(width: 400, height: 200)))

        // When
        let resultLoaded = await HarborImage.image(for: HImageRequest(url: imageURL("/big.jpg"), processors: [.resize(to: CGSize(width: 40, height: 40), mode: .fill)])).result
        let result = try XCTUnwrap(resultLoaded)

        // Then
        XCTAssertEqual(result.pixelSize, CGSize(width: 40, height: 40))
    }

    func testEXIFOrientationIsApplied() async throws {
        // Given: EXIF orientation 6 (displayed rotated 90° clockwise, so width and height swap)
        ImageStubProtocol.stub("/rotated.jpg", ImageStubResponse(body: TestImages.jpeg(width: 40, height: 20, orientation: 6)))

        // When
        let resultLoaded = await HarborImage.image(for: HImageRequest(url: imageURL("/rotated.jpg"))).result
        let result = try XCTUnwrap(resultLoaded)

        // Then
        XCTAssertEqual(result.pixelSize, CGSize(width: 20, height: 40))
    }

    func testEXIFRotatedImageIsDownsampledByItsDisplayedSize() async throws {
        // Given: 400x200 stored, displayed 200x400 (orientation 6)
        ImageStubProtocol.stub("/rotated.jpg", ImageStubResponse(body: TestImages.jpeg(width: 400, height: 200, orientation: 6)))
        let request = HImageRequest(url: imageURL("/rotated.jpg"), targetSize: HImageTargetSize(pixelWidth: 100, pixelHeight: 200, contentMode: .fit))

        // When
        let response = await HarborImage.image(for: request)

        // Then
        XCTAssertEqual(response.result?.pixelSize, CGSize(width: 100, height: 200))
    }

    func testIconWithSeveralSizesUsesTheLargestAndIsNotAnimated() async throws {
        // Given
        ImageStubProtocol.stub("/favicon.ico", ImageStubResponse(body: TestImages.ico(sizes: [16, 32])))

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/favicon.ico")))

        // Then
        let result = try XCTUnwrap(response.result)
        XCTAssertEqual(result.pixelSize, CGSize(width: 32, height: 32))
        XCTAssertNil(result.animation)
    }

    func testGIFWithoutALoopCountPlaysOnce() async throws {
        // Given
        ImageStubProtocol.stub("/once.gif", ImageStubResponse(body: TestImages.gif(colors: [.red, .green], loopCount: nil)))

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/once.gif")))

        // Then
        XCTAssertEqual(response.result?.animation?.loopCount, 1)
    }

    func testAnimatedGIFExposesItsFrames() async throws {
        // Given
        ImageStubProtocol.stub("/anim.gif", ImageStubResponse(body: TestImages.gif(colors: [.red, .green, .blue], delay: 0.2, loopCount: 3)))

        // When
        let resultLoaded = await HarborImage.image(for: HImageRequest(url: imageURL("/anim.gif"))).result
        let result = try XCTUnwrap(resultLoaded)

        // Then
        let animation = try XCTUnwrap(result.animation)
        XCTAssertEqual(animation.frameCount, 3)
        XCTAssertEqual(animation.loopCount, 3)
        XCTAssertEqual(animation.frameDurations.first ?? 0, 0.2, accuracy: 0.01)
        XCTAssertEqual(animation.duration, 0.6, accuracy: 0.03)
        let secondLoaded = await animation.frame(at: 1)
        let second = try XCTUnwrap(secondLoaded)
        XCTAssertTrue(TestImages.pixel(second, x: 4, y: 4).isClose(to: .green, tolerance: 20))
        let outOfRange = await animation.frame(at: 3)
        XCTAssertNil(outOfRange)
    }

    func testAnimatedFramesGetTheProcessorsAndTheOriginalIsCached() async throws {
        // Given
        ImageStubProtocol.stub("/anim.gif", ImageStubResponse(body: TestImages.gif(colors: [.red, .green], size: 16)))
        let request = HImageRequest(url: imageURL("/anim.gif"), processors: [.mask(.circle)])

        // When
        let resultLoaded = await HarborImage.image(for: request).result
        let result = try XCTUnwrap(resultLoaded)
        await HarborImage.clearCache(.memory)
        let fromDiskLoaded = await HarborImage.image(for: request).result
        let fromDisk = try XCTUnwrap(fromDiskLoaded)

        // Then
        let frameLoaded = await result.animation?.frame(at: 1)
        let frame = try XCTUnwrap(frameLoaded)
        XCTAssertEqual(TestImages.pixel(frame, x: 0, y: 0).alpha, 0)
        XCTAssertEqual(fromDisk.source, .disk)
        XCTAssertEqual(fromDisk.animation?.frameCount, 2, "The animation survives the disk cache")
    }

    func testCustomDecoderDecodesItsFormat() async throws {
        // Given
        HarborImage.registerDecoder(FakeDecoder())
        ImageStubProtocol.stub("/a.fake", ImageStubResponse(body: Data("FAKE".utf8)))

        // When
        let resultLoaded = await HarborImage.image(for: HImageRequest(url: imageURL("/a.fake"))).result
        let result = try XCTUnwrap(resultLoaded)

        // Then
        XCTAssertEqual(result.format, HImageFormat(rawValue: "fake"))
        XCTAssertEqual(result.pixelSize, CGSize(width: 3, height: 3))
    }

    func testCustomDecoderIsAskedBeforeTheBuiltInOnes() async throws {
        // Given: a decoder that claims PNG bytes
        HarborImage.registerDecoder(PNGOverrideDecoder())
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png(width: 40, height: 20, color: .red)))

        // When
        let resultLoaded = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png"))).result
        let result = try XCTUnwrap(resultLoaded)

        // Then: its image, not ImageIO's
        XCTAssertEqual(result.format, HImageFormat(rawValue: "png-override"))
        XCTAssertTrue(TestImages.pixel(result.image, x: 1, y: 1).isClose(to: .green))
    }

    func testCorruptedImageFailsToDecode() async {
        // Given: a PNG signature followed by garbage
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        data.append(Data(repeating: 7, count: 64))
        ImageStubProtocol.stub("/broken.png", ImageStubResponse(body: data))

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/broken.png")))

        // Then
        XCTAssertEqual(response.error, .decodingFailed)
    }

    func testSVGIsRasterizedAtTheTargetSize() async throws {
        // Given
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="blue"/></svg>"#
        ImageStubProtocol.stub("/icon.svg", ImageStubResponse(body: Data(svg.utf8)))

        // When
        let resultLoaded = await HarborImage.image(for: HImageRequest(url: imageURL("/icon.svg"), targetSize: HImageTargetSize(pixelWidth: 60, pixelHeight: 60))).result
        let result = try XCTUnwrap(resultLoaded)

        // Then: rendered at 60x60 pixels from a 10x10 document, not scaled up from a 10x10 bitmap
        XCTAssertEqual(result.format, .svg)
        XCTAssertEqual(result.pixelSize, CGSize(width: 60, height: 60))
        XCTAssertTrue(TestImages.pixel(result.image, x: 30, y: 30).isClose(to: .blue))
    }

    func testUnsupportedSVGFails() async {
        // Given
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><text>hi</text></svg>"#
        ImageStubProtocol.stub("/text.svg", ImageStubResponse(body: Data(svg.utf8)))

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/text.svg")))

        // Then
        guard case .unsupportedFormat = response.error else { return XCTFail("Unexpected \(String(describing: response.error))") }
    }
}

/// A decoder for a made-up format: bytes starting with "FAKE" decode to a 3x3 green image.
private struct FakeDecoder: HImageDecoder {
    let format = HImageFormat(rawValue: "fake")

    func canDecode(_ data: Data) -> Bool {
        data.starts(with: Data("FAKE".utf8))
    }

    func decode(_ data: Data, targetSize: HImageTargetSize?) throws -> CGImage {
        TestImages.image(width: 3, height: 3, color: .green)
    }
}

/// A decoder that claims every PNG and decodes it to a 3x3 green image.
private struct PNGOverrideDecoder: HImageDecoder {
    let format = HImageFormat(rawValue: "png-override")

    func canDecode(_ data: Data) -> Bool {
        HImageFormat.detect(data) == .png
    }

    func decode(_ data: Data, targetSize: HImageTargetSize?) throws -> CGImage {
        TestImages.image(width: 3, height: 3, color: .green)
    }
}
