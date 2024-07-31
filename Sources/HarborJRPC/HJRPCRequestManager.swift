//
//  HJRPCRequestManager.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

internal final class HJRPCRequestManager {
    internal static var config: HJRPCConfig = HJRPCConfig()
}

extension HJRPCRequestManager {

    static func request<Model: Codable>(model: Model.Type, request: any HJRPCRequestProtocol) async -> HJRPCResponse<Model> {
        guard !request.url.isEmpty else {
            return .error(.urlNeeded)
        }

        if request.needsAuth {
            if let authCredential = await Self.config.authProvider?.getAuthorizationHeader() {
                var mutableRequest = request
                var headerParameters = request.headers ?? [:]
                headerParameters[authCredential.key] = authCredential.value
                mutableRequest.headers = headerParameters

                let requestCopy = mutableRequest
                async let result = self.requestHandler(model: model, request: requestCopy)
                return await result
            } else {
                return .error(.authProviderNeeded)
            }
        } else {
            async let result = self.requestHandler(model: model, request: request)
            return await result
        }
    }

    private static func requestHandler<Model: Codable>(model: Model.Type, request: any HJRPCRequestProtocol) async -> HJRPCResponse<Model> {
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

