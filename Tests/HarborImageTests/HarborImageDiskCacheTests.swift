//
//  HarborImageDiskCacheTests.swift
//  HarborImageTests
//
//  The disk cache: file naming, LRU eviction, the index rebuilt from the files, clearing, and
//  the prefetcher that warms it up.
//

import XCTest
@testable import HarborCore
@testable import HarborImage

@HRequestManagerActor
final class HarborImageDiskCacheTests: XCTestCase {

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("HarborImageDisk-\(UUID().uuidString)", isDirectory: true)
        await ImageTestDefaults.restore(directory: directory)
    }

    override func tearDown() async throws {
        await ImageTestDefaults.tearDown()
        try? FileManager.default.removeItem(at: directory)
    }

    func testFilesAreNamedByTheDigestOfTheKey() async throws {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))

        // When
        _ = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png")))

        // Then
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files, [imageURL("/a.png").sha256Hex])
        let size = await HarborImage.diskCacheSize()
        XCTAssertEqual(size, TestImages.png().count)
    }

    func testLeastRecentlyUsedEntriesAreEvicted() async throws {
        // Given: a 1 MB cache and three entries of ~400 KB (eviction goes down to 90% of the capacity)
        let configuration = HImageCache.Configuration(diskCacheCapacityInMBs: 1, directory: directory)
        let payload = Data(repeating: 1, count: 400 * 1024)
        let disk = HImageDiskCache.shared

        // When
        await disk.store(payload, for: .original("first"), configuration: configuration) { true }
        try await Task.sleep(nanoseconds: 20_000_000)
        await disk.store(payload, for: .original("second"), configuration: configuration) { true }
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = await disk.data(for: .original("first"), configuration: configuration, allowsExpired: false)
        try await Task.sleep(nanoseconds: 20_000_000)
        await disk.store(payload, for: .original("third"), configuration: configuration) { true }

        // Then: "second" was the least recently used
        let first = await disk.data(for: .original("first"), configuration: configuration, allowsExpired: false)
        let second = await disk.data(for: .original("second"), configuration: configuration, allowsExpired: false)
        let third = await disk.data(for: .original("third"), configuration: configuration, allowsExpired: false)
        XCTAssertNotNil(first)
        XCTAssertNil(second)
        XCTAssertNotNil(third)
    }

    func testIndexIsRebuiltFromTheFiles() async throws {
        // Given
        let configuration = HImageCache.Configuration(directory: directory)
        let other = HImageCache.Configuration(directory: directory.appendingPathComponent("other"))
        let disk = HImageDiskCache.shared
        await disk.store(Data("bytes".utf8), for: .original("key"), configuration: configuration) { true }

        // When: another directory, then back, reloads the index from disk
        _ = await disk.count(configuration: other)
        let count = await disk.count(configuration: configuration)
        let data = await disk.data(for: .original("key"), configuration: configuration, allowsExpired: false)

        // Then
        XCTAssertEqual(count, 1)
        XCTAssertEqual(data, Data("bytes".utf8))
    }

    func testIsCurrentFalseDiscardsTheWrite() async throws {
        // Given
        let configuration = HImageCache.Configuration(directory: directory)

        // When
        await HImageDiskCache.shared.store(Data("bytes".utf8), for: .original("key"), configuration: configuration) { false }

        // Then
        let count = await HarborImage.diskCacheCount()
        XCTAssertEqual(count, 0)
    }

    func testObjectsAboveTheMaximumSizeAreNotStored() async throws {
        // Given
        let configuration = HImageCache.Configuration(maxObjectSizeInMBs: 1, directory: directory)

        // When
        await HImageDiskCache.shared.store(Data(count: 2 * 1024 * 1024), for: .original("big"), configuration: configuration) { true }

        // Then
        let count = await HarborImage.diskCacheCount()
        XCTAssertEqual(count, 0)
    }

    func testClearDiskRemovesTheFiles() async throws {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))
        _ = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png")))

        // When
        await HarborImage.clearCache(.disk)

        // Then
        let count = await HarborImage.diskCacheCount()
        XCTAssertEqual(count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(imageURL("/a.png").sha256Hex).path))
    }

    func testStoresOriginalWhenProcessedKeepsBothFiles() async throws {
        // Given
        HarborImage.setCacheConfiguration(HImageCache.Configuration(storesOriginalWhenProcessed: true, directory: directory))
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))

        // When
        _ = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png"), processors: [.grayscale]))

        // Then
        let count = await HarborImage.diskCacheCount()
        XCTAssertEqual(count, 2)
        let original = await HarborImage.data(for: HImageRequest(url: imageURL("/a.png"), cachePolicy: .returnCacheDontLoad))
        XCTAssertEqual(original.data, TestImages.png())
    }

    // MARK: - Prefetch

    func testPrefetchWarmsTheDiskAndReportsFailures() async throws {
        // Given
        let paths = (0..<5).map { "/p\($0).png" }
        for path in paths {
            ImageStubProtocol.stub(path, ImageStubResponse(body: TestImages.png(), delay: 0.05))
        }
        ImageStubProtocol.stub("/missing.png", ImageStubResponse(statusCode: 404))
        let requests: [any HImageRequestProtocol] = paths.map { HImageRequest(url: imageURL($0)) } + [HImageRequest(url: imageURL("/missing.png"))]

        // When
        let report = await HImagePrefetcher(maxConcurrent: 2).prefetch(requests)

        // Then
        XCTAssertEqual(report.completed, 5)
        XCTAssertEqual(report.failed, 1)
        let count = await HarborImage.diskCacheCount()
        XCTAssertEqual(count, 5)
        let cached = await HarborImage.image(for: HImageRequest(url: imageURL("/p0.png")))
        XCTAssertEqual(cached.result?.source, .disk, "Disk prefetching does not decode into memory")
    }

    func testPrefetchToMemory() async throws {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))

        // When
        await HImagePrefetcher(destination: .memoryAndDisk).prefetch([HImageRequest(url: imageURL("/a.png"))])

        // Then
        let cached = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png")))
        XCTAssertEqual(cached.result?.source, .memory)
    }

    func testPrefetcherCancelStopsPendingLoads() async throws {
        // Given
        let paths = (0..<4).map { "/slow\($0).png" }
        for path in paths {
            ImageStubProtocol.stub(path, ImageStubResponse(body: TestImages.png(), delay: 0.5))
        }
        let prefetcher = HImagePrefetcher(maxConcurrent: 1)

        // When
        prefetcher.start(paths.map { HImageRequest(url: imageURL($0)) })
        try await Task.sleep(nanoseconds: 100_000_000)
        prefetcher.cancel()
        try await Task.sleep(nanoseconds: 700_000_000)

        // Then
        XCTAssertLessThanOrEqual(ImageStubProtocol.requests().count, 2)
        let count = await HarborImage.diskCacheCount()
        XCTAssertEqual(count, 0)
    }
}
