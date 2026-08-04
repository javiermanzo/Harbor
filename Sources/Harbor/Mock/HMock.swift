//
//  HMock.swift
//  Harbor
//
//  Created by Javier Manzo on 06/11/2024.
//

import Foundation

/// Mock configuration for testing network requests.
/// Use this to simulate API responses during development and testing.
@HRequestManagerActor
public struct HMock {
    /// The request type to mock.
    public let request: HRequestBaseRequestProtocol.Type
    /// The HTTP status code to return.
    public let statusCode: Int
    /// Optional JSON response body.
    public let jsonResponse: String?
    /// Optional error to return instead of success.
    public let error: HRequestError?
    /// Optional delay in seconds before returning the response.
    public let delay: Double?
    /// Optional HTTP response headers (e.g. `Cache-Control`, `ETag`).
    public let headers: [String: String]?

    /// The name of the request type being mocked.
    public var requestName: String {
        "\(request.self)"
    }

    /// Creates a new mock configuration.
    /// - Parameters:
    ///   - request: The request type to mock
    ///   - statusCode: The HTTP status code to return
    ///   - jsonResponse: Optional JSON response body
    ///   - error: Optional error to return instead of success
    ///   - delay: Optional delay in seconds before returning the response
    ///   - headers: Optional HTTP response headers
    public init(request: HRequestBaseRequestProtocol.Type, statusCode: Int, jsonResponse: String? = nil, error: HRequestError? = nil, delay: Double? = nil, headers: [String: String]? = nil) {
        self.request = request
        self.statusCode = statusCode
        self.jsonResponse = jsonResponse
        self.error = error
        self.delay = delay
        self.headers = headers
    }
}
