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
    var retries: Int? { get }

    /// Additional HTTP headers to include in the request. Default: `nil`.
    var headers: [String: String]? { get }

    /// Parameters to send with the JSON-RPC request. Default: `nil`.
    var parameters: HJRPCParams? { get }

    /// Whether this request is a JSON-RPC notification. Notifications do not carry an `id`
    /// and the server does not respond to them. Default: `false`.
    var isNotification: Bool { get }

    /// The identifier to send with the request. Default: `nil` (a UUID-based identifier is generated).
    var requestID: HJRPCId? { get }

    /// Executes the JSON-RPC request asynchronously.
    /// - Returns: An `HJRPCResponse<Model>` containing either the result or an error.
    func requestResult() async -> HJRPCResponse<Model>

    /// Executes the JSON-RPC request asynchronously.
    /// - Returns: The decoded model on success.
    /// - Throws: An `HJRPCRequestError` when the request fails.
    func request() async throws -> Model

    /// Sends the JSON-RPC request as a notification. The request must have `isNotification` set to `true`.
    /// - Throws: `HJRPCRequestError.invalidRequest` if the request is not a notification, or another `HJRPCRequestError` when the request fails.
    func notify() async throws
}

// MARK: - Default Implementations

/// Default property implementations for `HJRPCRequestProtocol`.
public extension HJRPCRequestProtocol {
    var needsAuth: Bool { false }
    var retries: Int? { nil }
    var headers: [String: String]? { nil }
    var parameters: HJRPCParams? { nil }
    var isNotification: Bool { false }
    var requestID: HJRPCId? { nil }
}

/// Default request method implementations.
public extension HJRPCRequestProtocol {
    /// Handles JSON-RPC request execution with automatic protocol handling.
    func requestResult() async -> HJRPCResponse<Model> {
        return await HJRPCRequestManager.request(model: Model.self, request: self)
    }

    /// Executes the request and returns the decoded model, throwing on failure.
    func request() async throws -> Model {
        switch await requestResult() {
        case .success(let model):
            return model
        case .error(let error):
            throw error
        }
    }

    /// Sends the request as a JSON-RPC notification.
    func notify() async throws {
        guard isNotification else { throw HJRPCRequestError.invalidRequest }
        try await HJRPCRequestManager.notify(request: self)
    }
}

// MARK: - Internal Request Wrapping

/// Internal extension for wrapping JSON-RPC requests.
extension HJRPCRequestProtocol {
    /// Creates a Harbor-compatible request wrapper for this JSON-RPC request.
    @HRequestManagerActor
    func wrapRequest<RawModel: HModel>(type: RawModel.Type) -> HJRPCRequestWrapper<RawModel> {
        var jsonBody: [String: HJSONValue] = [
            "jsonrpc": .string(HJRPCRequestManager.config.jrpcVersion),
            "method": .string(method),
        ]

        var jrpcID: HJRPCId?
        if !isNotification {
            let effectiveID = requestID ?? .generated()
            jsonBody["id"] = effectiveID.jsonValue
            jrpcID = effectiveID
        }

        if let parameters {
            jsonBody["params"] = parameters.jsonValue
        }

        let debugType: HDebugRequestType = (self as? HDebugRequestProtocol)?.debugType ?? .none

        return HJRPCRequestWrapper<RawModel>(debugType: debugType, jsonBody: jsonBody, jrpcID: jrpcID, url: HJRPCRequestManager.config.url, needsAuth: needsAuth, retries: retries, pathParameters: nil, headerParameters: headers)
    }
}

// MARK: - Internal Request Wrapper

/// Internal wrapper that adapts JSON-RPC requests to Harbor's request protocol.
struct HJRPCRequestWrapper<RawModel: HModel>: Sendable, HPostRequestProtocol, HRequestWithResultProtocol {
    typealias Model = HJRPCResult<RawModel>

    let debugType: HDebugRequestType
    var bodyType: HRequestDataType = .json
    let jsonBody: [String: HJSONValue]
    let jrpcID: HJRPCId?
    let url: String
    let needsAuth: Bool
    var retries: Int?
    let pathParameters: [String: String]?
    var headerParameters: [String: String]?

    var bodyParameters: [String: Any]? {
        get { jsonBody.mapValues { $0.anyValue } }
        set { }
    }
}
