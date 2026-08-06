//
//  HarborStreamTests.swift
//  Harbor
//
//  Created by Javier Manzo on 20/07/2025.
//

import XCTest
@testable import Harbor

final class HarborStreamTests: XCTestCase {
    
    override func setUp() async throws {
        // Clear all cache before each test
        await Harbor.clearAllCache()
        await Harbor.removeAllMocks()
        await Harbor.setMocksOnlyInDebug(false)
        // Set default cache to disabled (original behavior)
        await Harbor.setDefaultCacheType(.disabled)
    }
    
    override func tearDown() async throws {
        // Clear all cache after each test
        await Harbor.clearAllCache()
        await Harbor.removeAllMocks()
        await setStubbedProtocolClasses(nil)
    }
    
    // MARK: - Request Stream Tests
    
    func testRequestStreamCacheOnly() async {
        let testData = TestStreamData(value: "stream-cache-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = HMock(request: TestStreamRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestStreamRequest()
        
        // First make a request to populate cache
        _ = await request.request()
        
        await Harbor.removeAllMocks() // Remove mock to ensure only cache is used
        
        // Test cache-only stream
        var results: [(TestStreamData, HOriginType)] = []
        do {
            for try await (response, origin) in request.requestStream(source: .cacheOnly) {
                results.append((response, origin))
            }
        } catch {
            XCTFail("Stream should not throw error when cache exists: \(error)")
        }
        
        XCTAssertEqual(results.count, 1, "Should get exactly one cache result")
        XCTAssertEqual(results.first?.0.value, "stream-cache-test")
        XCTAssertEqual(results.first?.1, .cache)
    }
    
    func testRequestStreamCacheOnlyNoCachedData() async {
        let request = TestStreamRequest()
        
        // Test cache-only stream with no cached data
        do {
            for try await _ in request.requestStream(source: .cacheOnly) {
                XCTFail("Should not yield any results when no cache exists")
            }
            XCTFail("Stream should throw noCachedDataFound error")
        } catch HRequestError.noCachedDataFound {
            // Expected error
        } catch {
            XCTFail("Should throw noCachedDataFound error, got: \(error)")
        }
    }
    
    func testRequestStreamRemoteOnly() async {
        let testData = TestStreamData(value: "stream-remote-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = HMock(request: TestStreamRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestStreamRequest()
        
        // Test remote-only stream
        var results: [(TestStreamData, HOriginType)] = []
        do {
            for try await (response, origin) in request.requestStream(source: .remoteOnly) {
                results.append((response, origin))
            }
        } catch {
            XCTFail("Stream should not throw error: \(error)")
        }
        
        XCTAssertEqual(results.count, 1, "Should get exactly one remote result")
        XCTAssertEqual(results.first?.0.value, "stream-remote-test")
        XCTAssertEqual(results.first?.1, .remote)
        
        await Harbor.removeAllMocks()
    }
    
    func testRequestStreamCacheAndRemote() async {
        let testData = TestStreamData(value: "stream-both-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = HMock(request: TestStreamRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestStreamRequest()
        
        // Populate cache before testing stream
        _ = await request.request()
        
        // Test cache-and-remote stream
        var results: [(TestStreamData, HOriginType)] = []
        do {
            let stream = request.requestStream(source: .cacheAndRemote)
            for try await (response, origin) in stream {
                results.append((response, origin))
            }
        } catch {
            XCTFail("Stream should not throw error: \(error)")
        }
        
        XCTAssertEqual(results.count, 2, "Should get both cache and remote results")
        XCTAssertEqual(results[0].0.value, "stream-both-test")
        XCTAssertEqual(results[0].1, .cache, "First result should be from cache")
        XCTAssertEqual(results[1].0.value, "stream-both-test")
        XCTAssertEqual(results[1].1, .remote, "Second result should be from remote")
        
        await Harbor.removeAllMocks()
    }
    
    func testRequestStreamCacheAndRemoteNoCache() async {
        let testData = TestStreamData(value: "stream-no-cache-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = HMock(request: TestStreamRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestStreamRequest()
        
        // Test cache-and-remote stream with no cache
        var results: [(TestStreamData, HOriginType)] = []
        do {
            for try await (response, origin) in request.requestStream(source: .cacheAndRemote) {
                results.append((response, origin))
            }
        } catch {
            XCTFail("Stream should not throw error: \(error)")
        }
        
        XCTAssertEqual(results.count, 1, "Should get only remote result when no cache")
        XCTAssertEqual(results.first?.0.value, "stream-no-cache-test")
        XCTAssertEqual(results.first?.1, .remote)
        
        await Harbor.removeAllMocks()
    }
    
    func testRequestStreamDefaultSource() async {
        let testData = TestStreamData(value: "stream-default-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = HMock(request: TestStreamRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestStreamRequest()
        
        // Test default source (should be .cacheAndRemote)
        var results: [(TestStreamData, HOriginType)] = []
        do {
            for try await (response, origin) in request.requestStream() {
                results.append((response, origin))
            }
        } catch {
            XCTFail("Stream should not throw error: \(error)")
        }
        
        // Should get only remote since no cache exists
        XCTAssertEqual(results.count, 1, "Should get only remote result when no cache and using default source")
        XCTAssertEqual(results.first?.0.value, "stream-default-test")
        XCTAssertEqual(results.first?.1, .remote)
        
        await Harbor.removeAllMocks()
    }
    
    func testRequestStreamNetworkError() async throws {
        LocalStubURLProtocol.clearStubs()
        LocalStubURLProtocol.registerStub(for: URL(string: "https://stream.example.com/data")!, data: Data(), response: HTTPURLResponse(), error: URLError(.notConnectedToInternet))
        await Harbor.setProtocolClasses([LocalStubURLProtocol.self])
        defer { Task { await Harbor.setProtocolClasses(nil) } }
        
        let request = TestStreamRequest()
        
        // No mock registered, should get network error for remote-only
        do {
            for try await _ in request.requestStream(source: .remoteOnly) {
                XCTFail("Should not yield any results when network fails")
            }
            XCTFail("Stream should throw network error")
        } catch {
            // Expected error (should be a network-related error)
            XCTAssertTrue(error is HRequestError, "Should throw HRequestError")
        }
    }
    
    func testRequestStreamCacheAndRemoteWithNetworkError() async throws {
        LocalStubURLProtocol.clearStubs()
        LocalStubURLProtocol.registerStub(for: URL(string: "https://stream.example.com/data")!, data: Data(), response: HTTPURLResponse(), error: URLError(.notConnectedToInternet))
        await Harbor.setProtocolClasses([LocalStubURLProtocol.self])
        defer { Task { await Harbor.setProtocolClasses(nil) } }
        
        let testData = TestStreamData(value: "stream-cache-with-error-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let mock = HMock(request: TestStreamRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        let request = TestStreamRequest()
        
        // First populate cache
        _ = await request.request()
        
        // Remove mock to simulate network error
        await Harbor.removeAllMocks()
        
        // Test cache-and-remote stream with network error
        var results: [(TestStreamData, HOriginType)] = []
        do {
            for try await (response, origin) in request.requestStream(source: .cacheAndRemote) {
                results.append((response, origin))
            }
            XCTFail("Stream should throw error when remote fails")
        } catch {
             // Expected error
        }
        
        // Should get only cache result since network fails
        XCTAssertEqual(results.count, 1, "Should get only cache result when network fails")
        XCTAssertEqual(results.first?.0.value, "stream-cache-with-error-test")
        XCTAssertEqual(results.first?.1, .cache)
    }

    /// Tests that a stream requesting data from cache only throws a `noCachedDataFound` error when the cached data has expired.
    func testRequestStreamCacheOnlyExpired() async {
        let testData = TestStreamData(value: "stream-expired-test", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData) else {
            XCTFail("Failed to encode test data")
            return
        }
        
        let request = TestStreamRequest()
        let url = "https://stream.example.com/data"
        
        // Manually store expired data in the cache (max-age=0 means it's immediately expired)
        let response = HTTPURLResponse(url: URL(string: url)!, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "max-age=0"])
        await HCache.Manager.shared.storeData(jsonData, forKey: url, config: HCache.Configuration(), response: response)
        await HCache.Manager.shared.waitForPendingDiskOperations()
        
        do {
            for try await _ in request.requestStream(source: .cacheOnly) {
                XCTFail("Should not yield any results when cache is expired")
            }
            XCTFail("Stream should throw noCachedDataFound error")
        } catch HRequestError.noCachedDataFound {
            // Expected error
        } catch {
            XCTFail("Should throw noCachedDataFound error, got: \(error)")
        }
    }
    
    /// Tests that a stream requesting data from both cache and remote recovers gracefully when the cached data fails to decode.
    /// It should ignore the invalid cache entry and proceed to yield the successful remote response.
    func testRequestStreamCacheAndRemoteDecodingError() async {
        let request = TestStreamRequest()
        let url = "https://stream.example.com/data"
        
        // Store invalid JSON data in the cache so decoding throws
        let invalidData = Data("invalid json".utf8)
        let cacheResponse = HTTPURLResponse(url: URL(string: url)!, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "max-age=3600"])
        await HCache.Manager.shared.storeData(invalidData, forKey: url, config: HCache.Configuration(), response: cacheResponse)
        await HCache.Manager.shared.waitForPendingDiskOperations()
        
        // Mock the remote response to succeed
        let testData = TestStreamData(value: "remote-after-cache-fail", timestamp: Date())
        guard let jsonData = try? JSONEncoder().encode(testData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to encode test data")
            return
        }
        let mock = HMock(request: TestStreamRequest.self, statusCode: 200, jsonResponse: jsonString)
        await Harbor.register(mock: mock)
        
        var results: [(TestStreamData, HOriginType)] = []
        var caughtError: Error?
        do {
            for try await (response, origin) in request.requestStream(source: .cacheAndRemote) {
                results.append((response, origin))
            }
        } catch {
            caughtError = error
        }
        
        XCTAssertNil(caughtError, "Stream should recover from cache decoding error and proceed to remote")
        XCTAssertEqual(results.count, 1, "Should only yield remote result since cache decoding failed")
        XCTAssertEqual(results.first?.0.value, "remote-after-cache-fail")
        XCTAssertEqual(results.first?.1, .remote)
        
        await Harbor.removeAllMocks()
    }

    func testRequestStreamCancellationCancelsUnderlyingRequest() async {
        // Given a stubbed session whose response only arrives after a delay
        await setStubbedProtocolClasses([DelayedResponseStubProtocol.self])
        await Harbor.setAssumeNetworkAvailableInDebug(true)
        DelayedResponseStubProtocol.reset()

        let request = TestStreamRequest()

        // When the stream is consumed in a child task that is cancelled mid-flight
        let consumer = Task {
            do {
                for try await _ in request.requestStream(source: .remoteOnly) { }
            } catch { }
        }

        let started = await waitUntil { DelayedResponseStubProtocol.startLoadingCalled }
        XCTAssertTrue(started, "The stub should have started loading before cancelling")

        consumer.cancel()

        // Then the cancellation reaches URLSession, which calls stopLoading on the stub
        let stopped = await waitUntil { DelayedResponseStubProtocol.stopLoadingCalled }
        XCTAssertTrue(stopped, "Cancelling the stream consumer should cancel the underlying request")

        _ = await consumer.value
    }

    /// Polls `condition` every 10ms until it holds or `timeout` elapses.
    private func waitUntil(timeout: TimeInterval = 2, condition: @escaping @Sendable () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}

// MARK: - Test Models and Requests

/// Mutates the actor-isolated `HConfig.protocolClasses` from nonisolated tests.
@HRequestManagerActor
private func setStubbedProtocolClasses(_ classes: [AnyClass]?) {
    Harbor.setProtocolClasses(classes)
}

/// URLProtocol stub injected through `HConfig.protocolClasses` that answers after a
/// delay, giving tests a window to cancel the request while it is in flight.
/// `stopLoading` records that URLSession cancelled the underlying request.
private final class DelayedResponseStubProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _startLoadingCalled = false
    nonisolated(unsafe) private static var _stopLoadingCalled = false

    static var startLoadingCalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _startLoadingCalled
    }

    static var stopLoadingCalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _stopLoadingCalled
    }

    static func reset() {
        lock.lock()
        _startLoadingCalled = false
        _stopLoadingCalled = false
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        Self.lock.lock()
        Self._startLoadingCalled = true
        Self.lock.unlock()

        // Respond asynchronously so `stopLoading` can run while the request is in flight.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            guard let url = self.request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data("delayed response".utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        Self.lock.lock()
        Self._stopLoadingCalled = true
        Self.lock.unlock()
    }
}
