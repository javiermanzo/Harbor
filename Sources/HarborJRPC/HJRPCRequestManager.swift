//
//  HJRPCRequestManager.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

final class HJRPCRequestManager {
    static var config: HJRPCConfig = HJRPCConfig()
}

extension HJRPCRequestManager {
    static func request<Model: Codable>(model: Model.Type, request: any HJRPCRequestProtocol) async -> HJRPCResponse<Model> {
        guard !request.url.isEmpty else {
            return .error(.urlNeeded)
        }

        let harborRequest = request.wrapRequest(type: model)
        let response: HResponseWithResult = await harborRequest.request()

        switch response {
        case .success(let result):
            if let model = result.result {
                return .success(model)
            } else if let error = result.error {
                return .error(.jrpcError(error: error))
            } else {
                return .error(.invalidRequest)
            }
        case .cancelled:
            return .cancelled
        case .error(let harborError):
            return .error(HJRPCRequestError.getError(hRequestError: harborError))
        }
    }
}

