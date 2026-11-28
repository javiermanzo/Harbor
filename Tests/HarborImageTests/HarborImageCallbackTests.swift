//
//  HarborImageCallbackTests.swift
//  HarborImageTests
//
//  The direct calls with optional callbacks (`image(for:onEvent:)`) and the `events(for:)`
//  sequence.
//

import XCTest
@testable import HarborCore
@testable import HarborImage

@HRequestManagerActor
final class HarborImageCallbackTests: XCTestCase {

    override func setUp() async throws {
        await ImageTestDefaults.restore()
    }

    override func tearDown() async throws {
        await ImageTestDefaults.tearDown()
    }

    func testEventsArriveInOrderOnTheMainActorBeforeReturning() async throws {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png(width: 200, height: 200), chunkSize: 4_000))
        let recorder = EventRecorder()

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png")), onEvent: { event in
            MainActor.assertIsolated()
            recorder.append(event)
        })

        // Then
        XCTAssertNotNil(response.result)
        let names = recorder.names
        XCTAssertEqual(names.first, "started")
        XCTAssertEqual(Array(names.suffix(2)), ["loaded(network)", "finished(success)"])
    }

    func testProgressIsReportedWhenTheSizeIsKnown() async throws {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png(width: 300, height: 300), chunkSize: 2_000))
        let recorder = EventRecorder()

        // When
        _ = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png")), onEvent: { recorder.append($0) })

        // Then
        let progress = recorder.all.compactMap { event -> Double? in
            if case .progress(let value) = event { return value }
            return nil
        }
        XCTAssertFalse(progress.isEmpty)
        XCTAssertEqual(progress, progress.sorted())
        XCTAssertEqual(progress.last ?? 0, 1, accuracy: 0.0001)
    }

    func testCallbackIsOptional() async {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))

        // When
        let response = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png")))

        // Then
        XCTAssertNotNil(response.result)
    }

    func testFailureIsDeliveredAsFinishedEvent() async {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(statusCode: 500))
        let recorder = EventRecorder()

        // When
        _ = await HarborImage.image(for: HImageRequest(url: imageURL("/a.png")), onEvent: { recorder.append($0) })

        // Then
        XCTAssertEqual(recorder.names, ["started", "finished(failure)"])
    }

    func testCancellingTheTaskStopsTheEvents() async throws {
        // Given
        ImageStubProtocol.stub("/slow.png", ImageStubResponse(body: TestImages.png(), delay: 1))
        let recorder = EventRecorder()
        let task = Task {
            await HarborImage.image(for: HImageRequest(url: imageURL("/slow.png")), onEvent: { recorder.append($0) })
        }
        try await Task.sleep(nanoseconds: 150_000_000)

        // When
        task.cancel()
        let response = await task.value
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertEqual(response.error, .cancelled)
        XCTAssertFalse(recorder.names.contains { $0.hasPrefix("finished") || $0.hasPrefix("loaded") })
    }

    func testEventsSequenceEndsAfterFinished() async {
        // Given
        ImageStubProtocol.stub("/a.png", ImageStubResponse(body: TestImages.png()))
        var events: [HImageEvent] = []

        // When
        for await event in HarborImage.events(for: HImageRequest(url: imageURL("/a.png"))) {
            events.append(event)
        }

        // Then
        guard case .started = events.first, case .finished(let response) = events.last else {
            return XCTFail("Unexpected events \(events)")
        }
        XCTAssertNotNil(response.result)
    }

    func testEventsSequenceReportsAnInvalidURL() async {
        // Given
        var last: HImageEvent?

        // When
        for await event in HarborImage.events(for: HImageRequest(url: "not a url")) {
            last = event
        }

        // Then
        guard case .finished(let response) = last, case .invalidURL = response.error else {
            return XCTFail("Expected an invalid URL, got \(String(describing: last))")
        }
    }
}
