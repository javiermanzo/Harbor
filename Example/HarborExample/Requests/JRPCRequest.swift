//
//  JRPCRequest.swift
//  HarborExample
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import HarborJRPC
import Harbor

/// `eth_blockNumber` takes no parameters, so `parameters` keeps its `nil` default.
struct JRPCRequest: HJRPCRequestProtocol, HDebugRequestProtocol {
    typealias Model = String
    let method: String = "eth_blockNumber"
    let debugType: HDebugRequestType = .requestAndResponse
    // JSON-RPC calls are POSTs: this read-only call opts in to retries after timeouts/5xx.
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 2, retryNonIdempotentRequests: true)
}
