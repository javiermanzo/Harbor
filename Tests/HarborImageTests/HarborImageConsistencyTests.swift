//
//  HarborImageConsistencyTests.swift
//  HarborImageTests
//
//  What the cache serves after the image changes: variants keyed by size, loads that start
//  after a clear, store and remove, animated images on disk, mocks, shared downloads, error
//  bodies, expired copies and the download limit.
//

import XCTest
@testable import HarborCore
@testable import HarborImage

@HRequestManagerActor
final class HarborImageConsistencyTests: XCTestCase {

    override func setUp() async throws {
        await ImageTestDefaults.restore()
    }

    override func tearDown() async throws {
        await ImageTestDefaults.tearDown()
    }

    // MARK: - Variants

    func testProcessedVariantIsCachedPerDecodingSize() async throws {
        // Given: a variant rendered from a 20x10 decode
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png(width: 400, height: 200)))
        let small = HImageRequest(url: imageURL("/a.png"), processors: [.grayscale], targetSize: HImageTargetSize(pixelWidth: 20, pixelHeight: 10, contentMode: .fit))
        _ = await HarborImage.image(for: small)
        await HarborImage.clearCache(.memory)

        // When: the same processing at full size
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png"), processors: [.grayscale]))

        // Then: not the small variant
        XCTAssertEqual(response.result?.pixelSize, CGSize(width: 400, height: 200))
    }

    func testAnimatedImageWithEncodingKeepsItsAnimationOnDisk() async throws {
        // Given
        ImageStubProtocol.stub("/anim.gif", ImageStubResponse(body: TestImages.gif(colors: [.red, .green])))
        let request = HImageRequest(url: imageURL("/anim.gif"), encoding: .png)
        _ = await HarborImage.image(for: request)
        await HarborImage.clearCache(.memory)

        // When
        let response = await HarborImage.image(for: request)

        // Then
        XCTAssertEqual(response.result?.source, .disk)
        XCTAssertEqual(response.result?.animation?.frameCount, 2)
    }

    // MARK: - Generations

    func testLoadAfterClearCacheDoesNotJoinTheEarlierDownload() async throws {
        // Given: a slow download of the previous account's image
        ImageStubProtocol.stub("/avatar.png",
                               ImageStubResponse(body: TestImages.png(color: .red), delay: 0.3),
                               ImageStubResponse(body: TestImages.png(color: .blue)))
        let request = HImageRequest(url: imageURL("/avatar.png"))
        async let earlier = HarborImage.image(for: request)
        try await Task.sleep(nanoseconds: 100_000_000)

        // When: the account changes and the image is requested again
        await HarborImage.clearCache()
        let later = await HarborImage.image(for: request)
        _ = await earlier

        // Then
        XCTAssertTrue(TestImages.pixel(try XCTUnwrap(later.result?.image), x: 1, y: 1).isClose(to: .blue))
        XCTAssertEqual(ImageStubProtocol.requests(path: "/avatar.png").count, 2)
    }

    func testStoreReplacesEverySizeAndProcessing() async throws {
        // Given: the image cached at two sizes and processed
        ImageStubProtocol.stub("/avatar.png", ImageStubResponse(body: TestImages.png(width: 40, height: 40, color: .red)))
        let sized = HImageRequest(url: imageURL("/avatar.png"), targetSize: HImageTargetSize(pixelWidth: 20, pixelHeight: 20))
        let resized = HImageRequest(url: imageURL("/avatar.png"), processors: [.resize(to: CGSize(width: 10, height: 10))])
        _ = await HarborImage.image(for: sized)
        _ = await HarborImage.image(for: resized)

        // When
        let stored = await HarborImage.store(TestImages.png(width: 40, height: 40, color: .green), for: HImageRequest(url: imageURL("/avatar.png")))

        // Then
        XCTAssertTrue(stored)
        let sizedImageLoaded = await HarborImage.image(for: sized).result?.image
        let sizedImage = try XCTUnwrap(sizedImageLoaded)
        let resizedImageLoaded = await HarborImage.image(for: resized).result?.image
        let resizedImage = try XCTUnwrap(resizedImageLoaded)
        XCTAssertTrue(TestImages.pixel(sizedImage, x: 5, y: 5).isClose(to: .green))
        XCTAssertTrue(TestImages.pixel(resizedImage, x: 5, y: 5).isClose(to: .green))
        XCTAssertEqual(ImageStubProtocol.requests().count, 1)
    }

    func testDownloadInFlightDoesNotOverwriteStoredBytes() async throws {
        // Given
        ImageStubProtocol.stub("/avatar.png", ImageStubResponse(body: TestImages.png(color: .red), delay: 0.3))
        let request = HImageRequest(url: imageURL("/avatar.png"))
        async let inFlight = HarborImage.image(for: request)
        try await Task.sleep(nanoseconds: 100_000_000)

        // When
        await HarborImage.store(TestImages.png(color: .green), for: request)
        _ = await inFlight

        // Then
        let cachedLoaded = await HarborImage.cached(for: request)
        let cached = try XCTUnwrap(cachedLoaded)
        XCTAssertTrue(TestImages.pixel(cached.image, x: 1, y: 1).isClose(to: .green))
    }

    func testStoreSkipsRequestsThatDoNotUseTheDisk() async {
        // When
        let stored = await HarborImage.store(TestImages.png(), for: HImageRequest(url: imageURL("/private.png"), cacheType: .memoryOnly))

        // Then
        XCTAssertFalse(stored)
        let count = await HarborImage.diskCacheCount()
        XCTAssertEqual(count, 0)
    }

    func testRemoveDropsEveryCopy() async throws {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))
        _ = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png"), processors: [.grayscale]))
        _ = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png")))

        // When
        await HarborImage.remove(HImageRequest(url: imageURL("/a.png")))

        // Then
        let count = await HarborImage.diskCacheCount()
        XCTAssertEqual(count, 0)
        let cached = await HarborImage.cached(for: HImageRequest(url: imageURL("/a.png"), processors: [.grayscale]))
        XCTAssertNil(cached)
    }

    // MARK: - Mocks

    func testMockAnswersOfflineAndBeforeTheDisk() async throws {
        // Given: a cached image and an offline device
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png(color: .red)))
        _ = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png"), cacheType: .diskOnly))
        HarborImage.register(HImageMock(url: imageURL("/a.png"), data: TestImages.png(color: .green)))
        HRequestManager.connectivityMonitor = FakeImageConnectivityMonitor(connected: false)

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png"), cacheType: .diskOnly))

        // Then
        XCTAssertEqual(response.result?.source, .local)
        XCTAssertTrue(TestImages.pixel(try XCTUnwrap(response.result?.image), x: 1, y: 1).isClose(to: .green))
    }

    // MARK: - Downloads

    func testImageAndByteLoadsShareOneDownload() async throws {
        // Given
        ImageStubProtocol.stub("/shared.png", ImageStubResponse(body: TestImages.png(), delay: 0.2))
        let request = HImageRequest(url: imageURL("/shared.png"))

        // When
        async let bytes = HarborImage.data(for: request)
        async let image = HarborImage.image(for: request)
        let (bytesResponse, imageResponse) = await (bytes, image)

        // Then
        XCTAssertNotNil(bytesResponse.data)
        XCTAssertNotNil(imageResponse.result)
        XCTAssertEqual(ImageStubProtocol.requests(path: "/shared.png").count, 1)
    }

    func testErrorStatusWithALargeBodyIsRetriedInsteadOfTooLarge() async {
        // Given: a 503 whose body is above the limit
        HarborImage.setMaxDownloadSizeInMBs(1)
        ImageStubProtocol.stub("/flaky.png",
                               ImageStubResponse(statusCode: 503, headers: ["Retry-After": "0"], body: Data(count: 2 * 1024 * 1024)),
                               ImageStubResponse(body: TestImages.png()))
        let request = HImageRequest(url: imageURL("/flaky.png"), retryPolicy: HRetryPolicy(maxRetries: 1, baseDelay: 0, jitter: 0...0))

        // When
        let response = await HarborImage.image(for: request)

        // Then
        XCTAssertNotNil(response.result)
    }

    func testExpiredCopyIsServedWhenTheDownloadFails() async throws {
        // Given: an expired copy and a failing server
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HarborImageStale-\(UUID().uuidString)")
        HarborImage.setCacheConfiguration(HImageCache.Configuration(expirationTime: 0.05, directory: directory))
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()), ImageStubResponse(statusCode: 500))
        let request = HImageRequest(url: imageURL("/a.png"), cacheType: .diskOnly)
        _ = await HarborImage.image(for: request)
        try await Task.sleep(nanoseconds: 150_000_000)

        // When
        let response = await HarborImage.image(for: request)

        // Then
        XCTAssertEqual(response.result?.source, .disk)
        XCTAssertEqual(ImageStubProtocol.requests().count, 2)
    }

    func testNotFoundIsReportedEvenWithAnExpiredCopy() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HarborImageGone-\(UUID().uuidString)")
        HarborImage.setCacheConfiguration(HImageCache.Configuration(expirationTime: 0.05, directory: directory))
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()), ImageStubResponse(statusCode: 404))
        let request = HImageRequest(url: imageURL("/a.png"), cacheType: .diskOnly)
        _ = await HarborImage.image(for: request)
        try await Task.sleep(nanoseconds: 150_000_000)

        // When
        let response = await HarborImage.image(for: request)

        // Then
        XCTAssertEqual(response.error, .api(statusCode: 404))
    }

    func testRaisingTheLimitStartsQueuedDownloads() async throws {
        // Given: one slot, taken, and a download waiting
        let limiter = HImageLimiter()
        let first = await limiter.acquire(limit: 1)
        let waiting = Task { await limiter.acquire(limit: 1) }
        try await Task.sleep(nanoseconds: 50_000_000)

        // When
        let third = await limiter.acquire(limit: 3)

        // Then
        let waitingResult = await waiting.value
        XCTAssertTrue(first)
        XCTAssertTrue(waitingResult)
        XCTAssertTrue(third)
    }
}
