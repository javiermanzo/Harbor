//
//  HServiceError.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

public enum HServiceError: Error {
    case apiError(statusCode: Int, data: Data)
    case invalidHttpResponse
    case invalidRequest
    case authProviderNeeded
    case codableError
    case noConnectionError
    case malformedRequestError
    case timeoutError
}

