//
//  ImageStubProtocol.swift
//  HarborImageTests
//
//  A URLProtocol stub for image downloads, installed with `Harbor.setProtocolClasses(_:)`.
//  Only requests to the host `images.test` are intercepted. Answers are registered per URL path
//  and can be a sequence (one per request, the last one repeats); a path with no answer fails
//  with `URLError(.fileDoesNotExist)`. Every request is recorded with its headers.
//

import Foundation
import HarborCore

/// A canned answer.
struct ImageStubResponse: Sendable {
    /// The HTTP status code.
    var statusCode = 200
    /// Response headers; `Content-Length` is added from `body` unless set here.
    var headers: [String: String] = [:]
    /// The response body.
    var body = Data()
    /// Body chunk size, to exercise progress; `nil` sends the body at once.
    var chunkSize: Int?
    /// Delay before answering, in seconds.
    var delay: TimeInterval = 0
    /// A transport error instead of a response.
    var error: URLError?
}

/// A recorded request.
struct ImageStubRequest: Sendable {
    let url: URL
    let headers: [String: String]
}

final class ImageStubProtocol: URLProtocol, @unchecked Sendable {
    /// The shared stub state.
    private struct State: Sendable {
        var responses: [String: [ImageStubResponse]] = [:]
        var requests: [ImageStubRequest] = []
    }

    private static let state = HLockedState(State())

    /// Registers the answers for a path, used in order; the last one repeats.
    static func stub(_ path: String, _ responses: ImageStubResponse...) {
        state.withLock { $0.responses[path] = responses }
    }

    /// Removes every answer and recorded request.
    static func reset() {
        state.withLock { $0 = State() }
    }

    /// The recorded requests, optionally for one path.
    static func requests(path: String? = nil) -> [ImageStubRequest] {
        state.withLock { state in
            state.requests.filter { path == nil || $0.url.path == path }
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "images.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        let headers = request.allHTTPHeaderFields ?? [:]
        let response = Self.state.withLock { state -> ImageStubResponse? in
            state.requests.append(ImageStubRequest(url: url, headers: headers))
            guard var queue = state.responses[url.path], !queue.isEmpty else { return nil }
            let next = queue.count > 1 ? queue.removeFirst() : queue[0]
            state.responses[url.path] = queue
            return next
        }
        guard let response else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }

        let deliver = { [weak self] in
            guard let self else { return }
            if let error = response.error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            var headerFields = response.headers
            if headerFields["Content-Length"] == nil {
                headerFields["Content-Length"] = String(response.body.count)
            }
            let httpResponse = HTTPURLResponse(url: url, statusCode: response.statusCode, httpVersion: "HTTP/1.1", headerFields: headerFields)!
            self.client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            if let chunkSize = response.chunkSize, chunkSize > 0 {
                var offset = 0
                while offset < response.body.count {
                    let end = min(offset + chunkSize, response.body.count)
                    self.client?.urlProtocol(self, didLoad: response.body.subdata(in: offset..<end))
                    offset = end
                }
            } else {
                self.client?.urlProtocol(self, didLoad: response.body)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if response.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + response.delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {}
}
