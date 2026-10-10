//
//  HURLBuilderTests.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import XCTest
@testable import Harbor

@HRequestManagerActor
final class HURLBuilderTests: XCTestCase {

    func testPathParameterEncoding() async throws {
        let baseUrl = "https://api.example.com/users/{id}/details"
        // '?' should be encoded to prevent query injection
        // '/' is allowed in urlPathAllowed so it might remain depending on the implementation details,
        // but '?' is definitely not allowed in path without encoding if we want it to be part of the segment.
        let pathParameters = ["id": "user?name=test"]

        let url = try HURLBuilder.compositeURL(url: baseUrl, pathParameters: pathParameters)

        // We expect '?' to be encoded as %3F
        XCTAssertEqual(url.absoluteString, "https://api.example.com/users/user%3Fname=test/details")
    }

    func testPathParameterSimple() async throws {
        let baseUrl = "https://api.example.com/users/{id}"
        let pathParameters = ["id": "123"]

        let url = try HURLBuilder.compositeURL(url: baseUrl, pathParameters: pathParameters)

        XCTAssertEqual(url.absoluteString, "https://api.example.com/users/123")
    }

    func testQueryParametersMergeWithExistingQuery() async throws {
        let baseUrl = "https://api.example.com/x?foo=bar"
        let queryParameters = ["page": "1"]

        let url = try HURLBuilder.compositeURL(url: baseUrl, queryParameters: queryParameters)

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try XCTUnwrap(components.queryItems)
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "foo", value: "bar")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "page", value: "1")))
    }

    func testPathParameterWithTraversalSegmentThrows() async {
        let baseUrl = "https://api.example.com/users/{id}"

        for value in ["../admin", "foo/../../bar", ".."] {
            XCTAssertThrowsError(try HURLBuilder.compositeURL(url: baseUrl, pathParameters: ["id": value])) { error in
                guard case HRequestError.malformedRequest = error else {
                    return XCTFail("Expected malformedRequest but got: \(error)")
                }
            }
        }
    }

    func testCompositeURLIsDeterministic() async throws {
        let baseUrl = "https://api.example.com/x?foo=bar"
        let queryParameters = ["page": "1", "limit": "10", "sort": "desc"]

        let first = try HURLBuilder.compositeURL(url: baseUrl, queryParameters: queryParameters)
        for _ in 0 ..< 10 {
            let url = try HURLBuilder.compositeURL(url: baseUrl, queryParameters: queryParameters)
            XCTAssertEqual(url.absoluteString, first.absoluteString)
        }
    }

    func testBuildUrlRequestFailureSurfacesReason() async {
        let service = MockInvalidRequest(url: "https://api.example.com")

        do {
            _ = try await HURLBuilder.buildUrlRequest(request: service)
            XCTFail("Expected buildUrlRequest to throw")
        } catch HRequestError.malformedRequest(let reason) {
            XCTAssertFalse(reason?.isEmpty ?? true, "The error should carry a concrete reason")
        } catch {
            XCTFail("Expected malformedRequest but got: \(error)")
        }
    }

    // MARK: - URL Scheme

    func testCompositeURLAcceptsHTTPAndHTTPSInAnyCase() async throws {
        let accepted = [("http://api.example.com/x", "http"), ("https://api.example.com/x", "https"),
                        ("HTTPS://api.example.com/x", "https"), ("HtTp://api.example.com/x", "http")]
        for (base, expectedScheme) in accepted {
            let url = try HURLBuilder.compositeURL(url: base)
            XCTAssertEqual(url.scheme?.lowercased(), expectedScheme, base)
        }
    }

    func testCompositeURLRejectsOtherSchemes() async throws {
        let rejected = ["file:///etc/passwd", "FILE:///etc/passwd", "ftp://example.com/x", "data:text/plain,hi", "javascript:alert(1)", "ws://example.com/socket"]
        for base in rejected {
            XCTAssertThrowsError(try HURLBuilder.compositeURL(url: base), base) { error in
                guard case HRequestError.malformedRequest(let reason) = error else {
                    return XCTFail("Expected malformedRequest for \(base) but got: \(error)")
                }
                XCTAssertTrue(reason?.contains("http") ?? false, "The reason should name the supported schemes")
            }
        }
    }

    func testCompositeURLRejectsAURLWithoutScheme() async throws {
        for base in ["invalid-url-format", "api.example.com/users", "/users", ""] {
            XCTAssertThrowsError(try HURLBuilder.compositeURL(url: base), base) { error in
                guard case HRequestError.malformedRequest = error else {
                    return XCTFail("Expected malformedRequest for \(base) but got: \(error)")
                }
            }
        }
    }

    func testSchemeRejectionReasonDoesNotLeakTheURL() async throws {
        XCTAssertThrowsError(try HURLBuilder.compositeURL(url: "ftp://user:hunter2@example.com/x")) { error in
            guard case HRequestError.malformedRequest(let reason) = error else {
                return XCTFail("Expected malformedRequest but got: \(error)")
            }
            XCTAssertFalse(reason?.contains("hunter2") ?? true)
        }
    }

    func testBuildUrlRequestRejectsFileURLsForEveryMethod() async {
        let requests: [any HRequestBaseRequestProtocol] = [
            MockGetRequest<MockModel>(url: "file:///etc/passwd"),
            MockPostRequest(url: "file:///etc/passwd"),
            MockPutRequest<MockModel>(url: "file:///etc/passwd"),
        ]
        for request in requests {
            do {
                _ = try await HURLBuilder.buildUrlRequest(request: request)
                XCTFail("Expected buildUrlRequest to throw for \(request.httpMethod)")
            } catch HRequestError.malformedRequest(let reason) {
                XCTAssertFalse(reason?.isEmpty ?? true)
            } catch {
                XCTFail("Expected malformedRequest but got: \(error)")
            }
        }
    }

    func testPathParameterCannotChangeTheScheme() async {
        let request = MockGetRequest<MockModel>(url: "{base}/users", pathParameters: ["base": "file:///etc"])
        do {
            _ = try await HURLBuilder.buildUrlRequest(request: request)
            XCTFail("Expected buildUrlRequest to throw")
        } catch HRequestError.malformedRequest {
            // Expected.
        } catch {
            XCTFail("Expected malformedRequest but got: \(error)")
        }
    }

    func testMockedRequestsWithHTTPSURLsStillWork() async throws {
        Harbor.setMocksEnabled(true)
        Harbor.removeAllMocks()
        defer { Harbor.removeAllMocks() }
        Harbor.register(mock: HMock(request: MockGetRequest<MockModel>.self, statusCode: 200, jsonResponse: #"{"quote":"mocked"}"#))

        let response = await MockGetRequest<MockModel>(url: "https://api.example.com/mocked").request()

        guard case .success(let model) = response else {
            return XCTFail("Expected the mocked response but got: \(response)")
        }
        XCTAssertEqual(model.quote, "mocked")
    }

    // MARK: - Timeout

    func testBuiltRequestCarriesThePerRequestTimeout() async throws {
        // Given a request overriding the timeout
        let request = TimeoutGetRequest(timeoutInterval: 42)

        // When
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)

        // Then the timeout is on the URLRequest, so it also holds for custom sessions
        XCTAssertEqual(urlRequest.timeoutInterval, 42, accuracy: 0.001)
    }

    func testBuiltRequestFallsBackToTheDefaultTimeout() async throws {
        // Given a default timeout and a request without an override
        Harbor.setDefaultTimeoutInterval(27)
        defer { Harbor.setDefaultTimeoutInterval(15) }

        // When
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: TimeoutGetRequest(timeoutInterval: nil))

        // Then
        XCTAssertEqual(urlRequest.timeoutInterval, 27, accuracy: 0.001)
    }
}

// MARK: - F18: Encoding And Validators

extension HURLBuilderTests {

    func testPlusInQueryValueIsPercentEncoded() async throws {
        let url = try HURLBuilder.compositeURL(url: "https://api.example.com/search", queryParameters: ["q": "a+b c"])

        XCTAssertEqual(url.absoluteString, "https://api.example.com/search?q=a%2Bb%20c")
        // A form decoder (where '+' means space) recovers the original value.
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first?.value, "a+b c")
    }

    func testQueryDelimitersInNamesAndValuesAreEncoded() async throws {
        let url = try HURLBuilder.compositeURL(url: "https://api.example.com/search",
                                               queryParameters: ["filter": "a&b=c#d", "k&=": "v"])

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try XCTUnwrap(components.queryItems)
        XCTAssertEqual(items.count, 2, "Delimiters must not split items: \(url)")
        XCTAssertTrue(items.contains(URLQueryItem(name: "filter", value: "a&b=c#d")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "k&=", value: "v")))
        XCTAssertNil(components.fragment)
    }

    func testBaseURLQueryIsKeptAsWritten() async throws {
        let url = try HURLBuilder.compositeURL(url: "https://api.example.com/x?sig=a%2Bb", queryParameters: ["page": "1"])

        XCTAssertEqual(url.absoluteString, "https://api.example.com/x?page=1&sig=a%2Bb")
    }

    func testDuplicateQueryNamesKeepTheirOrder() async throws {
        let url = try HURLBuilder.compositeURL(url: "https://api.example.com/x?tag=b&tag=a", queryParameters: ["page": "1"])

        XCTAssertEqual(url.absoluteString, "https://api.example.com/x?page=1&tag=b&tag=a")
    }

    func testSlashInPathParameterIsEncoded() async throws {
        let url = try HURLBuilder.compositeURL(url: "https://api.example.com/files/{name}/meta", pathParameters: ["name": "a/b"])

        // `pathComponents` decodes `%2F` on older Foundation versions, so assert on the encoded string only.
        XCTAssertEqual(url.absoluteString, "https://api.example.com/files/a%2Fb/meta")
    }

    func testTraversalGuardStillRejectsEncodedSlashTraversal() async {
        XCTAssertThrowsError(try HURLBuilder.compositeURL(url: "https://api.example.com/files/{name}", pathParameters: ["name": "../etc"]))
    }

    func testCallerProvidedValidatorsAreNotOverridden() async throws {
        // Given validators stored for the URL
        let request = ValidatorGetRequest(headerParameters: ["If-None-Match": "\"caller\""])
        let url = try XCTUnwrap(URL(string: request.url))
        let key = HCache.Manager.cacheKey(for: url, authHeader: nil)
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                                     headerFields: ["ETag": "\"stored\"", "Last-Modified": "Wed, 21 Oct 2015 07:28:00 GMT"]))
        await HCache.Manager.shared.storeData(Data("{\"quote\":\"q\"}".utf8), forKey: key, config: HCache.Configuration(), response: response)
        addTeardownBlock { await HCache.Manager.shared.clearAllCache() }

        // When the caller sets its own If-None-Match
        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)

        // Then it is kept and no stored validator is mixed in
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "If-None-Match"), "\"caller\"")
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "If-Modified-Since"))

        // And without caller validators the stored ones are injected
        let injected = try await HURLBuilder.buildUrlRequest(request: ValidatorGetRequest(headerParameters: nil))
        XCTAssertEqual(injected.value(forHTTPHeaderField: "If-None-Match"), "\"stored\"")
        XCTAssertEqual(injected.value(forHTTPHeaderField: "If-Modified-Since"), "Wed, 21 Oct 2015 07:28:00 GMT")
    }

    func testCallerProvidedIfModifiedSinceIsNotOverridden() async throws {
        let request = ValidatorGetRequest(url: "https://api.example.com/validators-ims", headerParameters: ["If-Modified-Since": "Thu, 01 Jan 2015 00:00:00 GMT"])
        let url = try XCTUnwrap(URL(string: request.url))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                                     headerFields: ["ETag": "\"stored\"", "Last-Modified": "Wed, 21 Oct 2015 07:28:00 GMT"]))
        await HCache.Manager.shared.storeData(Data("{\"quote\":\"q\"}".utf8), forKey: HCache.Manager.cacheKey(for: url, authHeader: nil),
                                              config: HCache.Configuration(), response: response)
        addTeardownBlock { await HCache.Manager.shared.clearAllCache() }

        let urlRequest = try await HURLBuilder.buildUrlRequest(request: request)

        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "If-Modified-Since"), "Thu, 01 Jan 2015 00:00:00 GMT")
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "If-None-Match"))
    }
}

/// GET request using the custom cache, with optional caller headers.
private struct ValidatorGetRequest: HGetRequestProtocol {
    typealias Model = MockModel
    var url = "https://api.example.com/validators"
    var headerParameters: [String: String]?
    var cacheType: HCache.CacheType? = .custom(HCache.Configuration())
}

/// GET request with an optional per-request timeout.
private struct TimeoutGetRequest: HGetRequestProtocol {
    typealias Model = MockModel
    let url = "https://api.example.com/timeout"
    var timeoutInterval: TimeInterval?
}
