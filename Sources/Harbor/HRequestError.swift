//
//  HRequestError.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

public enum HRequestError: Error, Sendable {
    case apiError(statusCode: Int, data: Data)
    case invalidHttpResponse
    case invalidRequest
    case authProviderNeeded
    case authNeeded
    case codableError(modelName: String, error: Error)
    case noConnectionError
    case malformedRequestError
    case timeoutError
    case cannotFindHost
    case cancelled
}
