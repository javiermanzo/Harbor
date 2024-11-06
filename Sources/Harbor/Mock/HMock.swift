//
//  HMock.swift
//  Harbor
//
//  Created by Javier Manzo on 06/11/2024.
//

import Foundation

@HRequestManagerActor
public struct HMock: Sendable {
    var request: HRequestBaseRequestProtocol.Type
    var statusCode: Int
    var jsonResponse: String?
    var error: HRequestError?

    var requestName: String {
        "\(request.self)"
    }

    public init(request: HRequestBaseRequestProtocol.Type, statusCode: Int, jsonResponse: String? = nil, error: HRequestError? = nil) {
        self.request = request
        self.statusCode = statusCode
        self.jsonResponse = jsonResponse
        self.error = error
    }
}
