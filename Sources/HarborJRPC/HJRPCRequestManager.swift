//
//  HJRPCRequestManager.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

@HRequestManagerActor
final class HJRPCRequestManager {
    static var config: HJRPCConfig = HJRPCConfig()
}

extension HJRPCRequestManager {
    static func request<Model: HModel>(model: Model.Type, request: any HJRPCRequestProtocol) async -> HJRPCResponse<Model> {
        guard !config.url.isEmpty else {
            return .error(.urlNeeded)
        }

        let harborRequest: HJRPCRequestWrapper = request.wrapRequest(type: model)
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

