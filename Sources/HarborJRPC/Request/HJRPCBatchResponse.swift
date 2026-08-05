//
//  HJRPCBatchResponse.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

/// The result of a single request inside a JSON-RPC batch response.
public enum HJRPCBatchResponse: Sendable {
    /// The request completed successfully with its raw JSON result and the identifier echoed by the server.
    case success(id: HJRPCId?, result: HJSONValue)
    /// The request failed with an error and the identifier echoed by the server.
    case error(id: HJRPCId?, error: HJRPCRequestError)
}

// MARK: - Internal Batch Wrapper

/// Internal wrapper that adapts a JSON-RPC batch payload to Harbor's request protocol.
struct HJRPCBatchWrapper: Sendable, HPostRequestProtocol, HRequestWithResultProtocol {
    typealias Model = [HJRPCResult<HJSONValue>]

    let debugType: HDebugRequestType
    var bodyType: HRequestDataType = .json
    let rawBody: Data?
    let requestIDs: [HJRPCId?]
    let url: String
    let needsAuth: Bool
    var retryPolicy: HRetryPolicy?
    let pathParameters: [String: String]?
    var headerParameters: [String: String]?

    var bodyParameters: [String: Any]? {
        get { nil }
        set { }
    }
}
