//
//  HMock.swift
//  Harbor
//
//  Created by Javier Manzo on 06/11/2024.
//

import Foundation

/// Mock configuration for testing network requests.
/// Use this to simulate API responses during development and testing.
public struct HMock: Sendable {
    /// The request type to mock.
    public let request: HRequestBaseRequestProtocol.Type
    /// The HTTP status code to return.
    public let statusCode: Int
    /// Optional JSON response body. When `nil`, the mock produces an empty body.
    public let jsonResponse: String?
    /// Optional error to return instead of success.
    public let error: HRequestError?
    /// Optional delay in seconds before returning the response.
    public let delay: Double?
    /// Optional HTTP response headers (e.g. `Cache-Control`, `ETag`).
    public let headers: [String: String]?

    /// Creates a new mock configuration.
    /// - Parameters:
    ///   - request: The request type to mock
    ///   - statusCode: The HTTP status code to return
    ///   - jsonResponse: Optional JSON response body
    ///   - error: Optional error to return instead of success
    ///   - delay: Optional delay in seconds before returning the response
    ///   - headers: Optional HTTP response headers
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

    /// Whether the mock has an explicit JSON body configured.
    var hasBody: Bool {
        jsonResponse != nil
    }
}
