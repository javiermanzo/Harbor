//
//  HJRPCDebugRequest.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor
import HarborCore

/// Internal wrapper that sends a JSON-RPC transport request with debug logging enabled.
struct HJRPCDebugRequest<Base: HJRPCTransportRequest>: Sendable {
    /// The wrapped transport request.
    let base: Base
    /// The debug type requested by the JSON-RPC request(s).
    let debugType: HDebugRequestType
}

// MARK: - HPostRequestProtocol

extension HJRPCDebugRequest: HPostRequestProtocol {
    /// Forwarded from `base`.
    var url: String { base.url }
    /// Forwarded from `base`.
    var needsAuth: Bool { base.needsAuth }
    /// Forwarded from `base`.
    var retryPolicy: HRetryPolicy? { base.retryPolicy }
    /// Forwarded from `base`.
    var headerParameters: [String: String]? { base.headerParameters }
    /// Forwarded from `base`.
    var timeoutInterval: TimeInterval? { base.timeoutInterval }
    /// Forwarded from `base`.
    var bodyParameters: [String: Any]? { base.bodyParameters }
    /// Forwarded from `base`.
    var rawBody: Data? { base.rawBody }
}

// MARK: - HRequestWithResultProtocol

extension HJRPCDebugRequest: HRequestWithResultProtocol {
    /// The model of the wrapped request.
    typealias Model = Base.Model

    /// Forwarded from `base`.
    func parseData<T: Codable>(data: Data, model: T.Type) throws -> T {
        try base.parseData(data: data, model: model)
    }
}

// MARK: - HDebugRequestProtocol

extension HJRPCDebugRequest: HDebugRequestProtocol {}
