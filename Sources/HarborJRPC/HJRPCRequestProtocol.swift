//
//  HJRPCRequestProtocol.swift
//  
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

public protocol HJRPCRequestProtocol: Sendable {
    associatedtype Model: HModel
    var method: String { get }
    var needsAuth: Bool { get }
    var retries: Int? { get set}
    var headers: [String: String]? { get set }
    var parameters: [String: Any]? { get set }

    func request() async -> HJRPCResponse<Model>
}

public extension HJRPCRequestProtocol {
    func request() async -> HJRPCResponse<Model> {
        return await HJRPCRequestManager.request(model: Model.self, request: self)
    }
}

extension HJRPCRequestProtocol {
    @HRequestManagerActor
    func wrapRequest<T: HModel>(type: T.Type) -> HJRPCRequestWrapper<T> {
        var jsonRPCBody: [String: Any] = [:]

        jsonRPCBody["jsonrpc"] = HJRPCRequestManager.config.jrpcVersion
        jsonRPCBody["method"] = method
        jsonRPCBody["id"] = UUID().uuidString
        jsonRPCBody["params"] = parameters

        let debugType: HDebugRequestType = (self as? HDebugRequestProtocol)?.debugType ?? .none

        let request = HJRPCRequestWrapper<T>(debugType: debugType, bodyParameters: jsonRPCBody, url: HJRPCRequestManager.config.url, needsAuth: needsAuth, retries: retries, headerParameters: headers)
        return request
    }
}

struct HJRPCRequestWrapper<Model: HModel>: @unchecked Sendable, HPostRequestProtocol, HRequestWithResultProtocol {
    var debugType: HDebugRequestType
    typealias Model = HJRPCResult<Model>
    var bodyType: HRequestDataType = .json
    var bodyParameters: [String : Any]?
    var url: String
    var needsAuth: Bool
    var retries: Int?
    var pathParameters: [String : String]?
    var headerParameters: [String : String]?
}

