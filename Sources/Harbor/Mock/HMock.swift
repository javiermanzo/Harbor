//
//  HMock.swift
//  Harbor
//
//  Created by Javier Manzo on 06/11/2024.
//

import Foundation

/// A canned response for every request of a given type, used to develop and test without a server.
///
/// Mocks are resolved inside Harbor's request pipeline, per attempt, so status handling,
/// retries, authentication and decoding run exactly as for a real response. Register one with
/// `Harbor.register(mock:)`; it only answers while mocks are enabled (`Harbor.setMocksEnabled(_:)`,
/// on by default in DEBUG builds).
///
/// ```swift
/// await Harbor.register(mock: HMock(request: GetUserRequest.self, statusCode: 200,
///                                   jsonResponse: #"{"id": 1, "name": "Jane"}"#))
/// ```
public struct HMock: Sendable {
    /// The request type to mock.
    public let request: HRequestBaseRequestProtocol.Type
    /// The HTTP status code to return.
    public let statusCode: Int
    /// Optional JSON response body. When `nil`, the mock produces an empty body.
    public let jsonResponse: String?
    /// Optional error the attempt fails with instead of producing a response (e.g. `.timeout`).
    /// It goes through the retry policy like the real failure it stands for.
    public let error: HRequestError?
    /// Optional delay in seconds before returning the response.
    public let delay: Double?
    /// Optional HTTP response headers (e.g. `Cache-Control`, `ETag`).
    public let headers: [String: String]?

    /// Creates a new mock configuration.
    /// - Parameters:
    ///   - request: The request type to mock.
    ///   - statusCode: The HTTP status code to return.
    ///   - jsonResponse: Optional JSON response body. Default: `nil` (empty body).
    ///   - error: Optional error the attempt fails with instead of producing a response.
    ///   - delay: Optional delay in seconds before the response is delivered.
    ///   - headers: Optional HTTP response headers.
    public init(request: HRequestBaseRequestProtocol.Type,
                statusCode: Int,
                jsonResponse: String? = nil,
                error: HRequestError? = nil,
                delay: Double? = nil,
                headers: [String: String]? = nil) {
        self.request = request
        self.statusCode = statusCode
        self.jsonResponse = jsonResponse
        self.error = error
        self.delay = delay
        self.headers = headers
    }
}

extension HMock {
    /// The response bytes for this mock. Returns empty data when no JSON body is configured.
    var responseBody: Data {
        jsonResponse?.data(using: .utf8) ?? Data()
    }
}
