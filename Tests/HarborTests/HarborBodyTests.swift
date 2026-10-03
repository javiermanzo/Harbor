//
//  HarborBodyTests.swift
//
//
//  Created by Jalil on 18/06/24.
//

import XCTest
@testable import Harbor

@HRequestManagerActor
final class HarborBodyTests: XCTestCase {

    func testBuildRequestWithMultipartBodyType() async throws {
        let service = MockPostBodyRequest(url: "https://example.com", bodyParameters: ["foo": "bar"], bodyType: .multipart)

        let url = URL(string: service.url)
        let request = try await HURLBuilder.buildUrlRequest(request: service)

        XCTAssertEqual(request.url, url)
        let contentType = try XCTUnwrap(request.allHTTPHeaderFields?["Content-Type"])
        XCTAssert(contentType.contains("Boundary-"))
    }

    func testBuildRequestWithEmptyMultipartBodyParameters() async throws {
        let service = MockPostBodyRequest(url: "https://example.com", bodyParameters: nil, bodyType: .multipart)

        let url = URL(string: service.url)
        let request = try await HURLBuilder.buildUrlRequest(request: service)

        XCTAssertEqual(request.url, url)
        XCTAssertNil(request.allHTTPHeaderFields?["Content-Type"])
    }

    func testBuildRequestWithJsonBodyType() async throws {
        let service = MockPostBodyRequest(url: "https://example.com", bodyParameters: ["foo": "bar"], bodyType: .json)
        let expectedContentType = "application/json"

        let url = URL(string: service.url)
        let request = try await HURLBuilder.buildUrlRequest(request: service)

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], expectedContentType)
    }

    func testMultipartRejectsNewlineInName() async {
        XCTAssertThrowsError(try HURLBuilder.convertFormField(named: "na\r\nme", value: "value", using: "Boundary-test")) { error in
            guard case HRequestError.malformedRequest = error else {
                return XCTFail("Expected malformedRequest but got: \(error)")
            }
        }
    }

    func testMultipartRejectsNewlineInValue() async {
        XCTAssertThrowsError(try HURLBuilder.convertFormField(named: "name", value: "va\r\nlue", using: "Boundary-test")) { error in
            guard case HRequestError.malformedRequest = error else {
                return XCTFail("Expected malformedRequest but got: \(error)")
            }
        }
    }

    func testMultipartRejectsQuoteInName() async {
        XCTAssertThrowsError(try HURLBuilder.convertFormField(named: "na\"me", value: "value", using: "Boundary-test")) { error in
            guard case HRequestError.malformedRequest = error else {
                return XCTFail("Expected malformedRequest but got: \(error)")
            }
        }
    }

    func testMultipartRejectsBoundaryInValue() async {
        XCTAssertThrowsError(try HURLBuilder.convertFormField(named: "name", value: "xxBoundary-testxx", using: "Boundary-test")) { error in
            guard case HRequestError.malformedRequest = error else {
                return XCTFail("Expected malformedRequest but got: \(error)")
            }
        }
    }

    func testMultipartBodyParametersStringifyScalars() async throws {
        let service = MockPostBodyRequest(url: "https://example.com", bodyParameters: ["count": 42, "flag": true], bodyType: .multipart)

        let request = try await HURLBuilder.buildUrlRequest(request: service)
        let body = try XCTUnwrap(request.httpBody)
        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertTrue(bodyString.contains("name=\"count\""))
        XCTAssertTrue(bodyString.contains("\r\n42\r\n"))
        XCTAssertTrue(bodyString.contains("name=\"flag\""))
        XCTAssertTrue(bodyString.contains("\r\ntrue\r\n"))
    }

    func testMultipartBodyWithFile() async throws {
        let fileContents = "multipart file contents"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-test-\(UUID().uuidString).txt")
        try Data(fileContents.utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let service = MockPostBodyRequest(url: "https://example.com", multipartBody: [
            "field": .text("hello"),
            "file": .file(url: fileURL, mimeType: "text/plain", fileName: "test.txt"),
        ])

        let request = try await HURLBuilder.buildUrlRequest(request: service)

        let contentType = try XCTUnwrap(request.allHTTPHeaderFields?["Content-Type"])
        XCTAssertTrue(contentType.contains("multipart/form-data"))

        let body = try XCTUnwrap(request.httpBody)
        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"field\""))
        XCTAssertTrue(bodyString.contains("\r\nhello\r\n"))
        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"file\"; filename=\"test.txt\""))
        XCTAssertTrue(bodyString.contains("Content-Type: text/plain"))
        XCTAssertTrue(bodyString.contains(fileContents))
    }

    func testMultipartBodyWithUnreadableFileThrows() async throws {
        let missingFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-missing-\(UUID().uuidString).txt")
        let service = MockPostBodyRequest(url: "https://example.com", multipartBody: [
            "file": .file(url: missingFileURL, mimeType: nil, fileName: nil),
        ])

        do {
            _ = try await HURLBuilder.buildUrlRequest(request: service)
            XCTFail("Expected buildUrlRequest to throw")
        } catch HRequestError.malformedRequest(let reason) {
            XCTAssertFalse(reason?.isEmpty ?? true, "The error should carry a concrete reason")
        } catch {
            XCTFail("Expected malformedRequest but got: \(error)")
        }
    }


    // MARK: - F18: Streamed Multipart Bodies

    private func makeTemporaryFile(_ data: Data) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-test-\(UUID().uuidString).bin")
        try data.write(to: fileURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }
        return fileURL
    }

    /// Temporary multipart body files currently on disk.
    private func multipartTemporaryFiles() throws -> Set<String> {
        let names = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
        return Set(names.filter { $0.hasPrefix("harbor-multipart-") })
    }

    func testStreamedMultipartBodyMatchesTheInMemoryEncoding() async throws {
        // A file spanning several read chunks
        let fileData = Data((0 ..< 200_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let fileURL = try makeTemporaryFile(fileData)
        let fields: [String: HFormValue] = ["file": .file(url: fileURL, mimeType: "application/octet-stream", fileName: "blob.bin"), "title": .text("hello")]

        let inMemory = try HURLBuilder.multipartDataBody(fields: fields, boundary: "Boundary-fixed")
        let bodyFile = try HURLBuilder.writeMultipartBody(fields: fields, boundary: "Boundary-fixed")
        defer { try? FileManager.default.removeItem(at: bodyFile) }

        XCTAssertEqual(try Data(contentsOf: bodyFile), inMemory)
        XCTAssertNotNil(inMemory.range(of: fileData))
    }

    func testBoundaryStraddlingTwoChunksIsDetected() async throws {
        // The delimiter starts a few bytes before the 64 KB chunk edge
        let boundary = "Boundary-straddle"
        var fileData = Data(repeating: 0x41, count: 64 * 1024 - 5)
        fileData.append(Data("--\(boundary)".utf8))
        fileData.append(Data(repeating: 0x42, count: 100))
        let fileURL = try makeTemporaryFile(fileData)
        let before = try multipartTemporaryFiles()

        XCTAssertThrowsError(try HURLBuilder.writeMultipartBody(fields: ["file": .file(url: fileURL, mimeType: nil, fileName: nil)], boundary: boundary)) { error in
            guard case HRequestError.malformedRequest = error else {
                return XCTFail("Expected malformedRequest but got: \(error)")
            }
        }
        XCTAssertEqual(try multipartTemporaryFiles(), before, "A failed encoding must not leave its temporary file behind")
    }

    func testPrepareRequestStreamsFilePartsAndKeepsTextOnlyBodiesInMemory() async throws {
        let fileURL = try makeTemporaryFile(Data("file contents".utf8))

        let withFile = try await HURLBuilder.prepareRequest(request: MockPostBodyRequest(url: "https://example.com", multipartBody: [
            "file": .file(url: fileURL, mimeType: "text/plain", fileName: "a.txt"),
        ]))
        defer { withFile.removeBodyFile() }
        let bodyFileURL = try XCTUnwrap(withFile.bodyFileURL)
        XCTAssertNil(withFile.urlRequest.httpBody)
        XCTAssertTrue(withFile.urlRequest.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertTrue(String(decoding: try Data(contentsOf: bodyFileURL), as: UTF8.self).contains("file contents"))

        withFile.removeBodyFile()
        XCTAssertFalse(FileManager.default.fileExists(atPath: bodyFileURL.path))

        let textOnly = try await HURLBuilder.prepareRequest(request: MockPostBodyRequest(url: "https://example.com", multipartBody: ["title": .text("hi")]))
        XCTAssertNil(textOnly.bodyFileURL)
        XCTAssertNotNil(textOnly.urlRequest.httpBody)
    }

    func testMultipartFileUploadStreamsFromDiskAndRemovesTheTemporaryFile() async throws {
        // Given a loopback server recording the request body
        let server = try LoopbackHTTPServer { _ in LoopbackHTTPResponse(statusCode: 200) }
        try await server.start()
        HRequestManager.connectivityMonitor = FakeConnectivityMonitor(connected: true)
        HConfig.shared.customURLSession = nil
        Harbor.removeAllMocks()
        Harbor.setProtocolClasses(nil)
        addTeardownBlock { @HRequestManagerActor in
            server.stop()
            HRequestManager.connectivityMonitor = HRequestManagerMonitor()
        }

        let fileData = Data((0 ..< 150_000).map { UInt8(truncatingIfNeeded: $0) })
        let fileURL = try makeTemporaryFile(fileData)
        let before = try multipartTemporaryFiles()
        let request = MockPostBodyRequest(url: "http://127.0.0.1:\(server.port)/upload", multipartBody: [
            "file": .file(url: fileURL, mimeType: "application/octet-stream", fileName: "blob.bin"),
            "title": .text("hello"),
        ])

        // When
        let response = await request.request()

        // Then the full body reached the server and the temporary file is gone
        if case .error(let error) = response {
            XCTFail("Expected success but got \(error)")
        }
        let received = try XCTUnwrap(server.receivedRequests.first)
        XCTAssertTrue(received.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertEqual(received.headers["content-length"], String(received.body.count))
        XCTAssertNotNil(received.body.range(of: fileData), "The file contents must be sent intact")
        XCTAssertNotNil(received.body.range(of: Data("\r\nhello\r\n".utf8)))
        XCTAssertEqual(try multipartTemporaryFiles(), before, "The temporary body file must be deleted after the request")
    }

    func testMockedMultipartFileUploadStillWorks() async throws {
        // Mocks short-circuit before the body is built, so no temporary file is involved.
        Harbor.setMocksEnabled(true)
        let mock = HMock(request: MockPostBodyRequest.self, statusCode: 200)
        Harbor.register(mock: mock)
        addTeardownBlock { @HRequestManagerActor in
            Harbor.removeAllMocks()
            Harbor.setMocksEnabled(nil)
        }
        let fileURL = try makeTemporaryFile(Data("x".utf8))

        let response = await MockPostBodyRequest(url: "https://example.com/upload", multipartBody: [
            "file": .file(url: fileURL, mimeType: nil, fileName: nil),
        ]).request()

        if case .error(let error) = response {
            XCTFail("Expected success but got \(error)")
        }
    }
}
