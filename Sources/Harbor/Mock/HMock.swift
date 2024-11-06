//
//  HMock.swift
//  Harbor
//
//  Created by Javier Manzo on 06/11/2024.
//

import Foundation

@HRequestManagerActor
public struct HMock: Sendable {
    let request: HRequestBaseRequestProtocol.Type
    let statusCode: Int
    let delay: Double?
    let jsonResponse: String?
    let error: HRequestError?

    var requestName: String {
        "\(request.self)"
    }

    public init(request: HRequestBaseRequestProtocol.Type, statusCode: Int, delay: Double? = nil, jsonResponse: String? = nil, error: HRequestError? = nil) {
        self.request = request
        self.statusCode = statusCode
        self.delay = delay
        self.jsonResponse = jsonResponse
        self.error = error
    }
}
