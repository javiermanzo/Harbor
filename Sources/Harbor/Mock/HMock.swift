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
    let request: HRequestBaseRequestProtocol.Type
    /// The HTTP status code to return.
    let statusCode: Int
    /// Optional JSON response body.
    let jsonResponse: String?
    /// Optional error to return instead of success.
    let error: HRequestError?
    /// Optional delay in seconds before returning the response.
    let delay: Double?

    /// The name of the request type being mocked.
    var requestName: String {
        "\(request.self)"
    }

    /// Creates a new mock configuration.
    /// - Parameters:
    ///   - request: The request type to mock
    ///   - statusCode: The HTTP status code to return
    ///   - jsonResponse: Optional JSON response body
    ///   - error: Optional error to return instead of success
    ///   - delay: Optional delay in seconds before returning the response
    public init(request: HRequestBaseRequestProtocol.Type, statusCode: Int, jsonResponse: String? = nil, error: HRequestError? = nil, delay: Double? = nil) {
        self.request = request
        self.statusCode = statusCode
        self.jsonResponse = jsonResponse
        self.error = error
        self.delay = delay
    }
}
