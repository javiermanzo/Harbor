//
//  HJRPCRequestProtocol.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

// MARK: - HJRPCRequestProtocol

/// Protocol for defining JSON-RPC 2.0 requests.
///
/// Provides typed JSON-RPC requests that integrate with Harbor networking framework.
/// Automatically handles JSON-RPC 2.0 specification requirements including request structure,
/// unique ID generation, and error response handling.
///
/// All conforming types must be `Sendable` for thread safety.
public protocol HJRPCRequestProtocol: Sendable {
    /// The model type that this request returns. Must conform to `HModel`.
    associatedtype Model: HModel
    
    /// The JSON-RPC method name to call.
    var method: String { get }
    
    /// Whether this request requires authentication. Default: `false`.
    var needsAuth: Bool { get }
    
    /// Optional number of retry attempts for failed requests. Default: `nil`.
    var retries: Int? { get set }
    
    /// Additional HTTP headers to include in the request. Default: `nil`.
    var headers: [String: String]? { get set }
    
    /// Parameters to send with the JSON-RPC request. Default: `nil`.
    var parameters: [String: Any]? { get }

    /// Executes the JSON-RPC request asynchronously.
    /// - Returns: An `HJRPCResponse<Model>` containing either the result or an error.
    func request() async -> HJRPCResponse<Model>
}

// MARK: - Default Implementations

/// Default property implementations for `HJRPCRequestProtocol`.
public extension HJRPCRequestProtocol {
    var needsAuth: Bool { false }
    var retries: Int? { get { nil } set { } }
    var headers: [String: String]? { get { nil } set { } }
    var parameters: [String: Any]? { nil }
}

/// Default request method implementation.
public extension HJRPCRequestProtocol {
    /// Handles JSON-RPC request execution with automatic protocol handling.
    func request() async -> HJRPCResponse<Model> {
        return await HJRPCRequestManager.request(model: Model.self, request: self)
    }
}

// MARK: - Internal Request Wrapping

/// Internal extension for wrapping JSON-RPC requests.
extension HJRPCRequestProtocol {
    /// Creates a Harbor-compatible request wrapper for this JSON-RPC request.
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

// MARK: - Internal Request Wrapper

/// Internal wrapper that adapts JSON-RPC requests to Harbor's request protocol.
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

