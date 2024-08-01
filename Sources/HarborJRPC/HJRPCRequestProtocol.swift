//
//  HJRPCRequestProtocol.swift
//  
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

public protocol HJRPCRequestProtocol {
    associatedtype Model: Codable
    var method: String { get }
    var needsAuth: Bool { get }
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
    var url: String { HJRPCRequestManager.config.url }

    func wrapRequest<T: Codable>(type: T.Type) -> HJRPCRequestWrapper<T> {
        var jsonRPCBody: [String: Any] = [:]

        jsonRPCBody["jsonrpc"] = HJRPCRequestManager.config.jrpcVersion
        jsonRPCBody["method"] = method
        jsonRPCBody["id"] = UUID().uuidString
        jsonRPCBody["params"] = parameters

        let debugType: HDebugRequestType = (self as? HDebugRequestProtocol)?.debugType ?? .none

        let request = HJRPCRequestWrapper<T>(debugType: debugType, bodyParameters: jsonRPCBody, url: url, needsAuth: needsAuth, headerParameters: headers)
        return request
    }
}

struct HJRPCRequestWrapper<Model: Codable>: HPostRequestProtocol, HRequestWithResultProtocol, HDebugRequestProtocol {
    var debugType: HDebugRequestType
    typealias Model = HJRPCResult<Model>
    var bodyType: HRequestDataType = .json
    var bodyParameters: [String : Any]?
    var url: String
    var needsAuth: Bool
    var pathParameters: [String : String]?
    var headerParameters: [String : String]?
}

