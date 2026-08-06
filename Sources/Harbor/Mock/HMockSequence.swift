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
        public let statusCode: Int
        public let jsonResponse: String?
        public let error: HRequestError?
        public let headers: [String: String]?
        public let delay: Double?

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

    func response(at index: Int) -> Response {
        let safeIndex = max(0, min(index, responses.count - 1))
        return responses[safeIndex]
    }
}
