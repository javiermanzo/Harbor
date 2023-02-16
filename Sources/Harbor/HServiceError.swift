//
//  HServiceError.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

public enum HServiceError: Error {
    case apiError(statusCode: Int, errorData: Data)
    case authProviderNeeded
    case badResponseError
    case codableError
    case malformedRequestError
    case noConectionError
    case requestError(statusCode: Int, response: HTTPURLResponse)
    case timeoutError
}


