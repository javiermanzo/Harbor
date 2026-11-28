//
//  HarborImageLoaderTests.swift
//  HarborImageTests
//
//  The load pipeline: network through Harbor's shared pipeline (auth, retry), memory and disk
//  cache, cache policies, deduplication, cancellation, limits, fallbacks, offline behavior,
//  store and remove, `data(for:)`, local URLs and mocks.
//

import XCTest
@testable import HarborCore
@testable import HarborImage

@HRequestManagerActor
final class HarborImageLoaderTests: XCTestCase {

    override func setUp() async throws {
        await ImageTestDefaults.restore()
    }

    override func tearDown() async throws {
        await ImageTestDefaults.tearDown()
    }

    // MARK: - Network

    func testDownloadsDecodesAndReportsNetworkSource() async throws {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png(width: 40, height: 20)))

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png")))

        // Then
        let result = try XCTUnwrap(response.result)
        XCTAssertEqual(result.source, .network)
        XCTAssertEqual(result.format, .png)
        XCTAssertEqual(result.pixelSize, CGSize(width: 40, height: 20))
        XCTAssertTrue(TestImages.pixel(result.image, x: 5, y: 5).isClose(to: .red))
        XCTAssertEqual(ImageStubProtocol.requests().first?.headers["Accept"]?.hasPrefix("image/"), true)
    }

    func testSecondLoadComesFromMemory() async throws {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))
        let request = HImageRequest(url: imageURL("/a.png"))
        _ = await HarborImage.image(for: request)

        // When
        let response = await HarborImage.image(for: request)

        // Then
        XCTAssertEqual(response.result?.source, .memory)
        XCTAssertEqual(ImageStubProtocol.requests().count, 1)
    }

    func testLoadAfterClearingMemoryComesFromDisk() async throws {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))
        let request = HImageRequest(url: imageURL("/a.png"))
        _ = await HarborImage.image(for: request)
        await HarborImage.clearCache(.memory)

        // When
        let response = await HarborImage.image(for: request)

        // Then
        XCTAssertEqual(response.result?.source, .disk)
        XCTAssertEqual(ImageStubProtocol.requests().count, 1)
    }

    func testHTTPErrorFailsWithItsStatusCode() async {
        // Given
        ImageStubProtocol.stub("/missing.png", ImageStubResponse(statusCode: 404))

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/missing.png")))

        // Then
        XCTAssertEqual(response.error, .api(statusCode: 404))
    }

    func testHTMLServedWithOKIsNotAnImage() async {
        // Given
        ImageStubProtocol.stub("/page", ImageStubResponse(body: Data("<!DOCTYPE html><html><body>oops</body></html>".utf8)))

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/page")))

        // Then
        XCTAssertEqual(response.error, .notAnImage)
    }

    func testInvalidURLFails() async {
        // When
        let response = await HarborImage.image(for: HImageRequest(url: "ftp://images.test/a.png"))

        // Then
        guard case .invalidURL = response.error else {
            return XCTFail("Expected .invalidURL, got \(String(describing: response.error))")
        }
    }

    func testRetryableStatusIsRetriedPerPolicyAndReportsRetrying() async throws {
        // Given
        ImageStubProtocol.stub("/flaky.png",
                               ImageStubResponse(statusCode: 503, headers: ["Retry-After": "0"]),
                               ImageStubResponse(body: TestImages.png()))
        let request = HImageRequest(url: imageURL("/flaky.png"), retryPolicy: HRetryPolicy(maxRetries: 2, baseDelay: 0, jitter: 0...0))
        let events = EventRecorder()

        // When
        let response = await HarborImage.image(for: request, onEvent: { event in events.append(event) })

        // Then
        XCTAssertNotNil(response.result)
        XCTAssertEqual(ImageStubProtocol.requests(path: "/flaky.png").count, 2)
        XCTAssertTrue(events.names.contains("retrying(1)"))
    }

    func testDefaultRetryPolicyApplies() async {
        // Given
        HarborImage.setDefaultRetryPolicy(HRetryPolicy(maxRetries: 1, baseDelay: 0, jitter: 0...0))
        ImageStubProtocol.stub("/flaky.png", ImageStubResponse(statusCode: 500), ImageStubResponse(body: TestImages.png()))

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/flaky.png")))

        // Then
        XCTAssertNotNil(response.result)
    }

    // MARK: - Auth

    func testNeedsAuthWithoutProviderFails() async {
        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/private.png"), needsAuth: true))

        // Then
        XCTAssertEqual(response.error, .authProviderNeeded)
    }

    func testUnauthorizedRefreshesTheCredentialsAndRetries() async throws {
        // Given
        let provider = RotatingImageAuthProvider()
        Harbor.setAuthProvider(provider)
        ImageStubProtocol.stub("/private.png", ImageStubResponse(statusCode: 401), ImageStubResponse(body: TestImages.png()))

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/private.png"), needsAuth: true))

        // Then
        XCTAssertNotNil(response.result)
        let requests = ImageStubProtocol.requests(path: "/private.png")
        XCTAssertEqual(requests.map { $0.headers["Authorization"] }, ["Bearer token-0", "Bearer token-1"])
        let refreshCount = await provider.refreshCount
        XCTAssertEqual(refreshCount, 1)
    }

    func testCredentialsNeverReachTheCacheFiles() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HarborImageAuth-\(UUID().uuidString)")
        await ImageTestDefaults.restore(directory: directory)
        Harbor.setAuthProvider(RotatingImageAuthProvider())
        ImageStubProtocol.stub("/private.png", ImageStubResponse(body: TestImages.png()))

        // When
        _ = await HarborImage.image(for: HImageRequest(url: imageURL("/private.png"), needsAuth: true))

        // Then: the only file is named by the digest of the URL
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files, [imageURL("/private.png").sha256Hex])
        for file in files {
            let contents = try Data(contentsOf: directory.appendingPathComponent(file))
            XCTAssertNil(contents.range(of: Data("token-0".utf8)))
        }
    }

    func testReplacingTheAuthProviderDuringALoadDoesNotStoreIt() async throws {
        // Given
        ImageStubProtocol.stub("/slow.png", ImageStubResponse(body: TestImages.png(), delay: 0.3))
        let request = HImageRequest(url: imageURL("/slow.png"))

        // When
        async let response = HarborImage.image(for: request)
        try await Task.sleep(nanoseconds: 100_000_000)
        Harbor.setAuthProvider(RotatingImageAuthProvider())
        let result = await response

        // Then
        XCTAssertNotNil(result.result)
        let cached = await HarborImage.cached(for: request)
        XCTAssertNil(cached)
    }

    // MARK: - Deduplication and Cancellation

    func testConcurrentLoadsShareOneDownload() async throws {
        // Given
        ImageStubProtocol.stub("/shared.png", ImageStubResponse(body: TestImages.png(), delay: 0.2))
        let request = HImageRequest(url: imageURL("/shared.png"))

        // When
        async let first = HarborImage.image(for: request)
        async let second = HarborImage.image(for: request)
        let responses = await [first, second]

        // Then
        XCTAssertTrue(responses.allSatisfy { $0.result != nil })
        XCTAssertEqual(ImageStubProtocol.requests(path: "/shared.png").count, 1)
    }

    func testCancellingOneCallerKeepsTheSharedDownloadForTheOther() async throws {
        // Given
        ImageStubProtocol.stub("/shared.png", ImageStubResponse(body: TestImages.png(), delay: 0.3))
        let request = HImageRequest(url: imageURL("/shared.png"))
        let cancelled = Task { await HarborImage.image(for: request) }
        let kept = Task { await HarborImage.image(for: request) }
        try await Task.sleep(nanoseconds: 100_000_000)

        // When
        cancelled.cancel()

        // Then
        let cancelledResponse = await cancelled.value
        let keptResponse = await kept.value
        XCTAssertEqual(cancelledResponse.error, .cancelled)
        XCTAssertNotNil(keptResponse.result)
        XCTAssertEqual(ImageStubProtocol.requests(path: "/shared.png").count, 1)
    }

    func testCancellingTheOnlyCallerReturnsCancelledAtOnce() async throws {
        // Given
        ImageStubProtocol.stub("/slow.png", ImageStubResponse(body: TestImages.png(), delay: 2))
        let task = Task { await HarborImage.image(for: HImageRequest(url: imageURL("/slow.png"))) }
        try await Task.sleep(nanoseconds: 100_000_000)
        let start = Date()

        // When
        task.cancel()
        let response = await task.value

        // Then
        XCTAssertEqual(response.error, .cancelled)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    // MARK: - Limits

    func testDownloadAboveTheLimitFailsWithTooLarge() async {
        // Given
        HarborImage.setMaxDownloadSizeInMBs(1)
        ImageStubProtocol.stub("/huge.png", ImageStubResponse(body: Data(count: 2 * 1024 * 1024)))

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/huge.png")))

        // Then
        XCTAssertEqual(response.error, .tooLarge(maxBytes: 1024 * 1024))
    }

    func testImageAboveThePixelLimitFailsBeforeDecoding() async {
        // Given
        HarborImage.setMaxImagePixels(100)
        ImageStubProtocol.stub("/big.png", ImageStubResponse(body: TestImages.png(width: 40, height: 20)))

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/big.png")))

        // Then
        XCTAssertEqual(response.error, .tooManyPixels(maxPixels: 100))
    }

    // MARK: - Fallbacks

    func testFallbackURLIsTriedAfterANonRetryableFailure() async throws {
        // Given
        ImageStubProtocol.stub("/primary.png", ImageStubResponse(statusCode: 404))
        ImageStubProtocol.stub("/backup.png", ImageStubResponse(body: TestImages.png(color: .blue)))
        let request = HImageRequest(url: imageURL("/primary.png"), fallbackURLs: [imageURL("/backup.png")])

        // When
        let response = await HarborImage.image(for: request)

        // Then
        let result = try XCTUnwrap(response.result)
        XCTAssertTrue(TestImages.pixel(result.image, x: 1, y: 1).isClose(to: .blue))
        let cached = await HarborImage.cached(for: HImageRequest(url: imageURL("/primary.png")))
        XCTAssertNotNil(cached, "The fallback is cached under the key of the main URL")
    }

    // MARK: - Cache Policies and Offline

    func testOfflineWithoutCacheFailsWithNoConnection() async {
        // Given
        HRequestManager.connectivityMonitor = FakeImageConnectivityMonitor(connected: false)

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png")))

        // Then
        XCTAssertEqual(response.error, .noConnection)
    }

    func testOfflineServesAnExpiredDiskEntry() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HarborImageOffline-\(UUID().uuidString)")
        await ImageTestDefaults.restore(directory: directory)
        HarborImage.setCacheConfiguration(HImageCache.Configuration(expirationTime: 0.05, directory: directory))
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))
        let request = HImageRequest(url: imageURL("/a.png"), cacheType: .diskOnly)
        _ = await HarborImage.image(for: request)
        try await Task.sleep(nanoseconds: 150_000_000)
        HRequestManager.connectivityMonitor = FakeImageConnectivityMonitor(connected: false)

        // When
        let response = await HarborImage.image(for: request)

        // Then
        XCTAssertEqual(response.result?.source, .disk)
    }

    func testExpiredEntryIsDownloadedAgainWhenOnline() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HarborImageExpiry-\(UUID().uuidString)")
        HarborImage.setCacheConfiguration(HImageCache.Configuration(expirationTime: 0.05, directory: directory))
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))
        let request = HImageRequest(url: imageURL("/a.png"), cacheType: .diskOnly)
        _ = await HarborImage.image(for: request)
        try await Task.sleep(nanoseconds: 150_000_000)

        // When
        let response = await HarborImage.image(for: request)

        // Then
        XCTAssertEqual(response.result?.source, .network)
        XCTAssertEqual(ImageStubProtocol.requests().count, 2)
    }

    func testReturnCacheDontLoadNeverDownloads() async {
        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png"), cachePolicy: .returnCacheDontLoad))

        // Then
        XCTAssertEqual(response.error, .notCached)
        XCTAssertTrue(ImageStubProtocol.requests().isEmpty)
    }

    func testReloadIgnoringCacheDownloadsAgain() async {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png(color: .red)), ImageStubResponse(body: TestImages.png(color: .blue)))
        _ = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png")))

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png"), cachePolicy: .reloadIgnoringCache))

        // Then
        XCTAssertEqual(response.result?.source, .network)
        XCTAssertEqual(ImageStubProtocol.requests().count, 2)
    }

    func testNoStoreResponseIsNotWrittenToDisk() async {
        // Given
        ImageStubProtocol.stub("/private.png", ImageStubResponse(headers: ["Cache-Control": "private, no-store"], body: TestImages.png()))

        // When
        _ = await HarborImage.image(for: HImageRequest(url: imageURL("/private.png")))

        // Then
        let count = await HarborImage.diskCacheCount()
        XCTAssertEqual(count, 0)
    }

    func testMemoryOnlyNeverWritesToDisk() async {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))

        // When
        _ = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png"), cacheType: .memoryOnly))

        // Then
        let count = await HarborImage.diskCacheCount()
        XCTAssertEqual(count, 0)
    }

    func testDisabledCacheDownloadsEveryTime() async {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))
        let request = HImageRequest(url: imageURL("/a.png"), cacheType: .disabled)

        // When
        _ = await HarborImage.image(for: request)
        _ = await HarborImage.image(for: request)

        // Then
        XCTAssertEqual(ImageStubProtocol.requests().count, 2)
    }

    func testSignedURLsShareTheCacheWithIgnoredQueryParameters() async {
        // Given
        ImageStubProtocol.stub("/signed.png", ImageStubResponse(body: TestImages.png()))
        func request(_ signature: String) -> HImageRequest {
            HImageRequest(url: imageURL("/signed.png"), queryParameters: ["Signature": signature, "size": "m"], ignoredQueryParameters: ["Signature"])
        }
        _ = await HarborImage.image(for: request("a"))

        // When
        let response = await HarborImage.image(for: request("b"))

        // Then
        XCTAssertEqual(response.result?.source, .memory)
        XCTAssertEqual(ImageStubProtocol.requests().count, 1)
    }

    func testClearCacheDuringALoadDoesNotStoreIt() async throws {
        // Given
        ImageStubProtocol.stub("/slow.png", ImageStubResponse(body: TestImages.png(), delay: 0.3))
        let request = HImageRequest(url: imageURL("/slow.png"))

        // When
        async let response = HarborImage.image(for: request)
        try await Task.sleep(nanoseconds: 100_000_000)
        await HarborImage.clearCache()
        _ = await response

        // Then
        let cached = await HarborImage.cached(for: request)
        XCTAssertNil(cached)
    }

    func testStoreAndRemove() async throws {
        // Given
        let request = HImageRequest(url: imageURL("/uploaded.png"))

        // When
        let stored = await HarborImage.store(TestImages.png(color: .green), for: request)
        let afterStore = await HarborImage.cached(for: request)
        await HarborImage.remove(request)
        let afterRemove = await HarborImage.cached(for: request)

        // Then
        XCTAssertTrue(stored)
        XCTAssertTrue(TestImages.pixel(try XCTUnwrap(afterStore?.image), x: 1, y: 1).isClose(to: .green))
        XCTAssertNil(afterRemove)
        let rejected = await HarborImage.store(Data("not an image".utf8), for: request)
        XCTAssertFalse(rejected)
    }

    // MARK: - Data

    func testDataReturnsTheOriginalBytes() async {
        // Given
        let png = TestImages.png()
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: png))

        // When
        let response = await HarborImage.data(for: HImageRequest(url: imageURL("/a.png"), processors: [.grayscale]))

        // Then
        XCTAssertEqual(response.data, png)
        guard case .success(_, let format, let source) = response else { return XCTFail("Expected success") }
        XCTAssertEqual(format, .png)
        XCTAssertEqual(source, .network)
    }

    // MARK: - Local URLs and Mocks

    func testDataURLIsDecodedWithoutNetwork() async throws {
        // Given
        let url = "data:image/png;base64," + TestImages.png(color: .blue).base64EncodedString()

        // When
        let response = await HarborImage.image(for: HImageRequest(url: url))

        // Then
        let result = try XCTUnwrap(response.result)
        XCTAssertEqual(result.source, .local)
        XCTAssertTrue(TestImages.pixel(result.image, x: 1, y: 1).isClose(to: .blue))
        XCTAssertTrue(ImageStubProtocol.requests().isEmpty)
    }

    func testPercentEncodedSVGDataURLIsRendered() async throws {
        // Given: the shape the Example App uses
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><circle cx="5" cy="5" r="5" fill="#0000ff"/></svg>"##
        let url = "data:image/svg+xml;utf8," + (svg.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")

        // When
        let response = await HarborImage.image(for: HImageRequest(url: url, targetSize: HImageTargetSize(pixelWidth: 40, pixelHeight: 40)))

        // Then
        let result = try XCTUnwrap(response.result)
        XCTAssertEqual(result.format, .svg)
        XCTAssertEqual(result.pixelSize, CGSize(width: 40, height: 40))
        XCTAssertTrue(TestImages.pixel(result.image, x: 20, y: 20).isClose(to: .blue))
    }

    func testFileURLIsRead() async throws {
        // Given
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-image-\(UUID().uuidString).png")
        try TestImages.png(color: .green).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        // When
        let response = await HarborImage.image(for: HImageRequest(url: file.absoluteString))

        // Then
        XCTAssertEqual(response.result?.source, .local)
    }

    func testMockIsServedInDebugBuilds() async throws {
        // Given
        HarborImage.register(HImageMock(url: imageURL("/mocked.png"), data: TestImages.png(color: .green)))
        HarborImage.register(HImageMock(url: imageURL("/mocked-error.png"), error: .api(statusCode: 500)))

        // When
        let success = await HarborImage.image(for: HImageRequest(url: imageURL("/mocked.png")))
        let failure = await HarborImage.image(for: HImageRequest(url: imageURL("/mocked-error.png")))

        // Then
        XCTAssertEqual(success.result?.source, .local)
        XCTAssertEqual(failure.error, .api(statusCode: 500))
        XCTAssertTrue(ImageStubProtocol.requests().isEmpty)
    }

    func testDebugRequestLoadsNormally() async {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))

        // When
        let response = await HarborImage.image(for: DebugImageRequest(url: imageURL("/a.png") + "?token=secret"))

        // Then
        XCTAssertNotNil(response.result)
    }
}
