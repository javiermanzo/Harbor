//
//  HJRPCRequestError.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

public enum HJRPCRequestError: Error, Sendable {
    case apiError(statusCode: Int, data: Data)
    case jrpcError(error: HJSONRPCError)
    case urlNeeded
    case invalidHttpResponse
    case invalidRequest
    case authProviderNeeded
    case authNeeded
    case codableError
    case noConnectionError
    case malformedRequestError
    case timeoutError
}

extension HJRPCRequestError {
    static func getError(hRequestError: HRequestError) -> HJRPCRequestError {
        switch hRequestError {
        case .apiError(let statusCode, let data):
            return .apiError(statusCode: statusCode, data: data)
        case .invalidHttpResponse:
            return .invalidHttpResponse
        case .invalidRequest:
            return .invalidRequest
        case .authProviderNeeded:
            return .authProviderNeeded
        case .authNeeded:
            return .authNeeded
        case .codableError:
            return .codableError
        case .noConnectionError:
            return .noConnectionError
        case .malformedRequestError:
            return .malformedRequestError
        case .timeoutError:
            return .timeoutError
        }
    }
}