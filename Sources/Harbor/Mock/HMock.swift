//
//  HMock.swift
//  Harbor
//
//  Created by Javier Manzo on 06/11/2024.
//

import Foundation

@HRequestManagerActor
public struct HMock {
    let request: HRequestBaseRequestProtocol.Type
    let statusCode: Int
    let jsonResponse: String?
    let error: HRequestError?
    let delay: Double?

    var requestName: String {
        "\(request.self)"
    }

    public init(request: HRequestBaseRequestProtocol.Type, statusCode: Int, jsonResponse: String? = nil, error: HRequestError? = nil, delay: Double? = nil) {
        self.request = request
        self.statusCode = statusCode
        self.jsonResponse = jsonResponse
        self.error = error
        self.delay = delay
    }
}
