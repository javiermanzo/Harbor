//
//  HMockSequence.swift
//  Harbor
//

import Foundation

/// A scripted sequence of mock responses for a request type, played back in order.
///
/// Register a sequence with `Harbor.registerSequence(_:)`. Each request of the given type
/// resolves to the next response; after the last one is consumed it repeats indefinitely.
public struct HMockSequence: Sendable {
    /// One response in a mock sequence.
    public struct Response: Sendable {
        /// The HTTP status code to return.
        public let statusCode: Int
        /// Optional JSON response body.
        public let jsonResponse: String?
        /// Optional error to return instead of success.
        public let error: HRequestError?
        /// Optional HTTP response headers.
        public let headers: [String: String]?
        /// Optional delay in seconds before returning the response.
        public let delay: Double?

        /// Creates a new response for a sequence.
        /// - Parameters:
        ///   - statusCode: The HTTP status code to return
        ///   - jsonResponse: Optional JSON response body
        ///   - error: Optional error to return instead of success
        ///   - headers: Optional HTTP response headers
        ///   - delay: Optional delay in seconds before returning the response
        public init(statusCode: Int,
                    jsonResponse: String? = nil,
                    error: HRequestError? = nil,
                    headers: [String: String]? = nil,
                    delay: Double? = nil) {
            self.statusCode = statusCode
            self.jsonResponse = jsonResponse
            self.error = error
            self.headers = headers
            self.delay = delay
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

    /// Convenience to build a sequence from raw `HMock` configurations, sharing their
    /// status/body/error/headers/delay.
    public init(request: HRequestBaseRequestProtocol.Type, mocks: [HMock]) {
        self.request = request
        self.responses = mocks.map {
            Response(statusCode: $0.statusCode,
                     jsonResponse: $0.jsonResponse,
                     error: $0.error,
                     headers: $0.headers,
                     delay: $0.delay)
        }
    }

    /// Returns the response at the given index, clamping to the last available response.
    func response(at index: Int) -> Response {
        let safeIndex = max(0, min(index, responses.count - 1))
        return responses[safeIndex]
    }
}
