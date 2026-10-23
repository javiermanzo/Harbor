//
//  HMockSequence.swift
//  Harbor
//

import Foundation
import HarborCore

/// A scripted sequence of mock responses for a request type, played back in order.
///
/// Register a sequence with `Harbor.register(mockSequence:)`. Each attempt of a request of the
/// given type (retries included) resolves to the next response; after the last one is consumed
/// it repeats indefinitely. Use it to script a failure followed by a success, a token refresh, …
///
/// ```swift
/// await Harbor.register(mockSequence: HMockSequence(request: GetUserRequest.self, responses: [
///     .init(statusCode: 503),
///     .init(statusCode: 200, jsonResponse: #"{"id": 1, "name": "Jane"}"#)
/// ]))
/// ```
public struct HMockSequence: Sendable {
    /// One response in a mock sequence.
    public struct Response: Sendable {
        /// The HTTP status code to return.
        public let statusCode: Int
        /// Optional JSON response body. When `nil`, the response has an empty body.
        public let jsonResponse: String?
        /// Optional error the attempt fails with instead of producing a response. It goes
        /// through the retry policy like the real failure it stands for.
        public let error: HRequestError?
        /// Optional delay in seconds before returning the response, capped at
        /// `HRetryPolicy.maxDelay` (60 s). Cancelling the request ends it early.
        public let delay: Double?
        /// Optional HTTP response headers (e.g. `Cache-Control`, `ETag`, `Retry-After`).
        public let headers: [String: String]?

        /// Creates a new response for a sequence. The parameters follow the order of
        /// `HMock(request:statusCode:jsonResponse:error:delay:headers:)`.
        /// - Parameters:
        ///   - statusCode: The HTTP status code to return
        ///   - jsonResponse: Optional JSON response body
        ///   - error: Optional error to return instead of success
        ///   - delay: Optional delay in seconds before returning the response
        ///   - headers: Optional HTTP response headers
        public init(statusCode: Int,
                    jsonResponse: String? = nil,
                    error: HRequestError? = nil,
                    delay: Double? = nil,
                    headers: [String: String]? = nil) {
            self.statusCode = statusCode
            self.jsonResponse = jsonResponse
            self.error = error
            self.delay = delay
            self.headers = headers
        }
    }

    /// The request type this sequence mocks.
    public let request: HRequestBaseRequestProtocol.Type
    /// The responses to play back, in order.
    public let responses: [Response]

    /// Creates a new sequence from an array of `Response` objects.
    /// - Parameters:
    ///   - request: The request type this sequence mocks.
    ///   - responses: The responses to play back, in order.
    public init(request: HRequestBaseRequestProtocol.Type, responses: [Response]) {
        self.request = request
        self.responses = responses
    }

    /// Returns the response at the given index, clamping to the last available response.
    /// - Parameter index: The zero-based position in `responses`.
    func response(at index: Int) -> Response {
        let safeIndex = max(0, min(index, responses.count - 1))
        return responses[safeIndex]
    }
}
