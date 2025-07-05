//
//  HJRPCRequestProtocol.swift
//  
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

/// Protocol for defining JSON-RPC requests.
/// Implement this protocol to create typed JSON-RPC requests.
public protocol HJRPCRequestProtocol: Sendable {
    /// The model type that this request returns.
    associatedtype Model: HModel
    /// The JSON-RPC method name to call.
    var method: String { get }
    /// Whether this request requires authentication.
    var needsAuth: Bool { get }
    /// Optional number of retry attempts for failed requests.
    var retries: Int? { get set}
    /// Additional HTTP headers to include in the request.
    var headers: [String: String]? { get set }
    /// Parameters to send with the JSON-RPC request.
    var parameters: [String: Any]? { get set }

    /// Executes the JSON-RPC request.
    /// - Returns: An `HJRPCResponse` containing either the result or an error.
    func request() async -> HJRPCResponse<Model>
}

/// Default implementation of the request method.
public extension HJRPCRequestProtocol {
    /// Default implementation that handles the JSON-RPC request execution.
    /// - Returns: An `HJRPCResponse` containing either the result or an error.
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

