//
//  HarborImageProcessingTests.swift
//  HarborImageTests
//
//  The built-in processors (checked pixel by pixel), custom processors, the encoding stage
//  and how processing interacts with the cache.
//

import XCTest
@testable import HarborCore
@testable import HarborImage

@HRequestManagerActor
final class HarborImageProcessingTests: XCTestCase {

    override func setUp() async throws {
        await ImageTestDefaults.restore()
    }

    override func tearDown() async throws {
        await ImageTestDefaults.tearDown()
    }

    private let context = HImageProcessingContext(format: .png)

    // MARK: - Geometry

    func testResizeClampsAnInfiniteOrNotANumberSize() async {
        // When
        let processor = HResizeProcessor(size: CGSize(width: 200, height: CGFloat.infinity), mode: .fit)
        let invalid = HResizeProcessor(size: CGSize(width: CGFloat.nan, height: -5), mode: .fit)

        // Then
        XCTAssertEqual(processor.size, CGSize(width: 200, height: 65_536))
        XCTAssertEqual(processor.decodingTarget.pixelHeight, 65_536)
        XCTAssertEqual(invalid.size, CGSize(width: 1, height: 1))
        XCTAssertEqual(invalid.identifier, "resize(1x1,fit,false)")
    }

    func testResizeFitKeepsTheAspectRatio() async throws {
        // When
        let output = try await HResizeProcessor(size: CGSize(width: 20, height: 20), mode: .fit).process(TestImages.image(width: 40, height: 20), context: context)

        // Then
        XCTAssertEqual(output.width, 20)
        XCTAssertEqual(output.height, 10)
    }

    func testResizeFillCoversAndCrops() async throws {
        // Given: red right half, blue left half
        let input = TestImages.image(width: 40, height: 20, color: .red, leftHalf: .blue)

        // When
        let output = try await HResizeProcessor(size: CGSize(width: 10, height: 10), mode: .fill).process(input, context: context)

        // Then
        XCTAssertEqual(output.width, 10)
        XCTAssertEqual(output.height, 10)
        XCTAssertTrue(TestImages.pixel(output, x: 1, y: 5).isClose(to: .blue))
        XCTAssertTrue(TestImages.pixel(output, x: 8, y: 5).isClose(to: .red))
    }

    func testResizeStretchAndNoUpscaling() async throws {
        // When
        let stretched = try await HResizeProcessor(size: CGSize(width: 10, height: 10), mode: .stretch).process(TestImages.image(width: 40, height: 20), context: context)
        let notUpscaled = try await HResizeProcessor(size: CGSize(width: 100, height: 100)).process(TestImages.image(width: 40, height: 20), context: context)
        let upscaled = try await HResizeProcessor(size: CGSize(width: 80, height: 80), allowsUpscaling: true).process(TestImages.image(width: 40, height: 20), context: context)

        // Then
        XCTAssertEqual(CGSize(width: stretched.width, height: stretched.height), CGSize(width: 10, height: 10))
        XCTAssertEqual(CGSize(width: notUpscaled.width, height: notUpscaled.height), CGSize(width: 40, height: 20))
        XCTAssertEqual(CGSize(width: upscaled.width, height: upscaled.height), CGSize(width: 80, height: 40))
    }

    func testCropBySizeAndAlignment() async throws {
        // Given
        let input = TestImages.image(width: 40, height: 20, color: .red, leftHalf: .blue)

        // When
        let leading = try await HCropProcessor(region: .size(CGSize(width: 10, height: 10), alignment: .leading)).process(input, context: context)
        let rect = try await HCropProcessor(region: .rect(CGRect(x: 30, y: 0, width: 10, height: 5))).process(input, context: context)

        // Then
        XCTAssertEqual(leading.width, 10)
        XCTAssertTrue(TestImages.pixel(leading, x: 5, y: 5).isClose(to: .blue))
        XCTAssertEqual(CGSize(width: rect.width, height: rect.height), CGSize(width: 10, height: 5))
        XCTAssertTrue(TestImages.pixel(rect, x: 5, y: 2).isClose(to: .red))
    }

    func testCropOutsideTheImageFails() async {
        do {
            _ = try await HCropProcessor(region: .rect(CGRect(x: 100, y: 100, width: 5, height: 5))).process(TestImages.image(width: 10, height: 10), context: context)
            XCTFail("Expected an error")
        } catch {
            guard case .processingFailed = error as? HImageError else { return XCTFail("Unexpected \(error)") }
        }
    }

    func testRotateAndFlip() async throws {
        // Given
        let input = TestImages.image(width: 40, height: 20, color: .red, leftHalf: .blue)

        // When
        let rotated = try await HRotateProcessor(degrees: 90).process(input, context: context)
        let flipped = try await HFlipProcessor(direction: .horizontal).process(input, context: context)

        // Then: clockwise, the left (blue) half ends at the top
        XCTAssertEqual(CGSize(width: rotated.width, height: rotated.height), CGSize(width: 20, height: 40))
        XCTAssertTrue(TestImages.pixel(rotated, x: 10, y: 5).isClose(to: .blue))
        XCTAssertTrue(TestImages.pixel(rotated, x: 10, y: 35).isClose(to: .red))
        XCTAssertTrue(TestImages.pixel(flipped, x: 2, y: 10).isClose(to: .red))
        XCTAssertTrue(TestImages.pixel(flipped, x: 38, y: 10).isClose(to: .blue))
    }

    func testPaddingAddsTransparentSpace() async throws {
        // When
        let output = try await HPaddingProcessor(insets: HImageEdgeInsets(top: 4, leading: 2, bottom: 0, trailing: 0)).process(TestImages.image(width: 10, height: 10), context: context)

        // Then
        XCTAssertEqual(CGSize(width: output.width, height: output.height), CGSize(width: 12, height: 14))
        XCTAssertEqual(TestImages.pixel(output, x: 0, y: 0).alpha, 0)
        XCTAssertTrue(TestImages.pixel(output, x: 6, y: 8).isClose(to: .red))
    }

    // MARK: - Masks and Borders

    func testCircleMaskCropsToASquareAndClearsTheCorners() async throws {
        // When
        let output = try await HMaskProcessor(shape: .circle).process(TestImages.image(width: 40, height: 20), context: context)

        // Then
        XCTAssertEqual(CGSize(width: output.width, height: output.height), CGSize(width: 20, height: 20))
        XCTAssertEqual(TestImages.pixel(output, x: 0, y: 0).alpha, 0)
        XCTAssertTrue(TestImages.pixel(output, x: 10, y: 10).isClose(to: .red))
    }

    func testRoundedCornersAndCapsule() async throws {
        // When
        let rounded = try await HMaskProcessor(shape: .roundedRect(radius: 8)).process(TestImages.image(width: 40, height: 20), context: context)
        let capsule = try await HMaskProcessor(shape: .capsule).process(TestImages.image(width: 40, height: 20), context: context)

        // Then
        XCTAssertEqual(TestImages.pixel(rounded, x: 0, y: 0).alpha, 0)
        XCTAssertTrue(TestImages.pixel(rounded, x: 20, y: 0).isClose(to: .red))
        XCTAssertEqual(TestImages.pixel(capsule, x: 1, y: 1).alpha, 0)
        XCTAssertTrue(TestImages.pixel(capsule, x: 20, y: 10).isClose(to: .red))
    }

    func testPathMaskUsesUnitCoordinatesFromTheTopLeft() async throws {
        // Given: the top half of the unit square
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: 1, height: 0.5), transform: nil)

        // When
        let output = try await HMaskProcessor(shape: .path(path, id: "top-half")).process(TestImages.image(width: 20, height: 20), context: context)

        // Then
        XCTAssertTrue(TestImages.pixel(output, x: 10, y: 3).isClose(to: .red))
        XCTAssertEqual(TestImages.pixel(output, x: 10, y: 16).alpha, 0)
    }

    func testImageMaskUsesItsAlpha() async throws {
        // Given: a mask opaque on the left half only
        let mask = TestImages.image(width: 20, height: 20, color: .clear, leftHalf: .black)

        // When
        let output = try await HMaskProcessor(shape: .image(mask, id: "left")).process(TestImages.image(width: 20, height: 20), context: context)

        // Then
        XCTAssertTrue(TestImages.pixel(output, x: 3, y: 10).isClose(to: .red))
        XCTAssertEqual(TestImages.pixel(output, x: 16, y: 10).alpha, 0)
    }

    func testBorderPaintsTheEdges() async throws {
        // When
        let output = try await HBorderProcessor(width: 4, color: .white).process(TestImages.image(width: 20, height: 20), context: context)

        // Then
        XCTAssertTrue(TestImages.pixel(output, x: 1, y: 10).isClose(to: .white))
        XCTAssertTrue(TestImages.pixel(output, x: 10, y: 10).isClose(to: .red))
    }

    // MARK: - Filters

    func testTintGrayscaleAdjustBlurAndOverlay() async throws {
        // Given
        let input = TestImages.image(width: 20, height: 20, color: .red)

        // When
        let tinted = try await HTintProcessor(color: HImageColor(red: 0, green: 0, blue: 1)).process(input, context: context)
        let gray = try await HColorAdjustProcessor(saturation: 0).process(input, context: context)
        let darker = try await HColorAdjustProcessor(brightness: -0.5).process(TestImages.image(width: 4, height: 4, color: .white), context: context)
        let blurred = try await HBlurProcessor(radius: 3).process(TestImages.image(width: 20, height: 20, color: .red, leftHalf: .blue), context: context)
        let overlaid = try await HOverlayProcessor(overlay: TestImages.image(width: 4, height: 4, color: .green), id: "badge", alignment: .topLeading).process(input, context: context)

        // Then
        XCTAssertTrue(TestImages.pixel(tinted, x: 10, y: 10).isClose(to: .blue))
        let grayPixel = TestImages.pixel(gray, x: 10, y: 10)
        XCTAssertEqual(grayPixel.red, grayPixel.green, accuracy: 3)
        XCTAssertEqual(grayPixel.green, grayPixel.blue, accuracy: 3)
        XCTAssertLessThan(TestImages.pixel(darker, x: 2, y: 2).red, 200)
        let edge = TestImages.pixel(blurred, x: 10, y: 10)
        XCTAssertTrue(edge.red > 20 && edge.blue > 20, "The halves blend at the edge: \(edge)")
        XCTAssertEqual(CGSize(width: blurred.width, height: blurred.height), CGSize(width: 20, height: 20))
        XCTAssertTrue(TestImages.pixel(overlaid, x: 1, y: 1).isClose(to: .green))
        XCTAssertTrue(TestImages.pixel(overlaid, x: 15, y: 15).isClose(to: .red))
    }

    func testIdentifiersDescribeTheConfiguration() async {
        // Then
        XCTAssertNotEqual(HBlurProcessor(radius: 1).identifier, HBlurProcessor(radius: 2).identifier)
        XCTAssertNotEqual(HMaskProcessor(shape: .circle).identifier, HMaskProcessor(shape: .capsule).identifier)
        XCTAssertEqual(HResizeProcessor(size: CGSize(width: 10, height: 10)).identifier, HResizeProcessor(size: CGSize(width: 10, height: 10)).identifier)
    }

    // MARK: - Pipeline

    func testRequestProcessorsAreAppliedAndTheVariantIsCached() async throws {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png(width: 40, height: 20)))
        let request = HImageRequest(url: imageURL("/a.png"), processors: [.resize(to: CGSize(width: 20, height: 20), mode: .fill), .mask(.circle)])

        // When
        let first = await HarborImage.image(for: request)
        await HarborImage.clearCache(.memory)
        let second = await HarborImage.image(for: request)

        // Then
        let result = try XCTUnwrap(first.result)
        XCTAssertEqual(result.pixelSize, CGSize(width: 20, height: 20))
        XCTAssertEqual(result.format, .png, "A processed image is kept as PNG, with alpha")
        XCTAssertEqual(TestImages.pixel(result.image, x: 0, y: 0).alpha, 0)
        XCTAssertEqual(second.result?.source, .disk)
        XCTAssertEqual(second.result?.pixelSize, CGSize(width: 20, height: 20))
        XCTAssertEqual(ImageStubProtocol.requests().count, 1)
    }

    func testCustomProcessorRunsAndIsPartOfTheKey() async throws {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))
        let plain = HImageRequest(url: imageURL("/a.png"))
        let custom = HImageRequest(url: imageURL("/a.png"), processors: [SolidColorProcessor(color: .green)])

        // When
        let plainResult = await HarborImage.image(for: plain).result
        let customResult = await HarborImage.image(for: custom).result

        // Then
        XCTAssertTrue(TestImages.pixel(try XCTUnwrap(plainResult?.image), x: 1, y: 1).isClose(to: .red))
        XCTAssertTrue(TestImages.pixel(try XCTUnwrap(customResult?.image), x: 1, y: 1).isClose(to: .green))
    }

    func testFailingProcessorFailsTheLoad() async {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png"), processors: [FailingProcessor()]))

        // Then
        guard case .processingFailed(let detail) = response.error else { return XCTFail("Unexpected \(String(describing: response.error))") }
        XCTAssertTrue(detail.hasPrefix("failing"))
    }

    func testProcessorsRunInTheOrderGiven() async throws {
        // Given
        let image = TestImages.image(width: 40, height: 40)

        // When: padding then crop, and crop then padding
        let padThenCrop = try await HarborImage.process(image, with: [.padding(HImageEdgeInsets(all: 10)), .crop(size: CGSize(width: 10, height: 10), alignment: .topLeading)])
        let cropThenPad = try await HarborImage.process(image, with: [.crop(size: CGSize(width: 10, height: 10), alignment: .topLeading), .padding(HImageEdgeInsets(all: 10))])

        // Then
        XCTAssertEqual(CGSize(width: padThenCrop.width, height: padThenCrop.height), CGSize(width: 10, height: 10))
        XCTAssertEqual(TestImages.pixel(padThenCrop, x: 5, y: 5).alpha, 0, "The crop keeps the transparent padding")
        XCTAssertEqual(CGSize(width: cropThenPad.width, height: cropThenPad.height), CGSize(width: 30, height: 30))
        XCTAssertTrue(TestImages.pixel(cropThenPad, x: 15, y: 15).isClose(to: .red))
    }

    func testProcessWithoutDownload() async throws {
        // When
        let output = try await HarborImage.process(TestImages.image(width: 40, height: 20), with: [.resize(to: CGSize(width: 10, height: 10), mode: .fit), .grayscale])

        // Then
        XCTAssertEqual(CGSize(width: output.width, height: output.height), CGSize(width: 10, height: 5))
    }

    // MARK: - Encoding

    func testEncodingFormats() async throws {
        // Given
        let image = TestImages.image(width: 64, height: 64)

        // When
        let jpeg = try await HarborImage.encode(image, as: .jpeg(quality: 0.8))
        let png = try await HarborImage.encode(image, as: .png)

        // Then
        XCTAssertEqual(HImageFormat.detect(jpeg), .jpeg)
        XCTAssertEqual(HImageFormat.detect(png), .png)
    }

    func testHEICEncodingProducesHEICWhereAvailable() async throws {
        // Given
        let available = (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains("public.heic")
        try XCTSkipUnless(available, "HEIC encoding is not available here")

        // When
        let heic = try await HarborImage.encode(TestImages.image(width: 64, height: 64), as: .heic(quality: 0.7))

        // Then
        XCTAssertEqual(HImageFormat.detect(heic), .heic)
    }

    func testMaxBytesLowersTheQuality() async throws {
        // Given: a noisy image compresses poorly at high quality
        let noisy = noiseImage(size: 128)
        let full = try await HarborImage.encode(noisy, as: .jpeg(quality: 1))
        let limit = full.count / 3

        // When
        let limited = try await HarborImage.encode(noisy, as: .jpeg(quality: 1, maxBytes: limit))

        // Then
        XCTAssertLessThanOrEqual(limited.count, limit)
    }

    func testImpossibleMaxBytesFails() async {
        do {
            _ = try await HarborImage.encode(noiseImage(size: 128), as: .jpeg(maxBytes: 10))
            XCTFail("Expected an error")
        } catch {
            guard case .encodingFailed = error else { return XCTFail("Unexpected \(error)") }
        }
    }

    func testRequestEncodingSetsTheResultData() async throws {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png(width: 64, height: 64)))

        // When
        let resultLoaded = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png"), encoding: .jpeg(quality: 0.5))).result
        let result = try XCTUnwrap(resultLoaded)

        // Then
        XCTAssertEqual(result.format, .jpeg)
        XCTAssertEqual(HImageFormat.detect(result.data), .jpeg)
    }

    /// A deterministic noisy image.
    private func noiseImage(size: Int) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        var seed: UInt32 = 42
        for index in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0..<3 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                bytes[index + channel] = UInt8(truncatingIfNeeded: seed >> 24)
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}
