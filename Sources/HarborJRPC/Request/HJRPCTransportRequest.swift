//
//  HJRPCTransportRequest.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor
import HarborCore

/// Shape shared by the internal single and batch wrappers that carry JSON-RPC payloads
/// through Harbor.
protocol HJRPCTransportRequest: HPostRequestProtocol, HRequestWithResultProtocol {
    /// The debug type to log with, or `nil` when no wrapped request opted into logging
    /// by conforming to `HDebugRequestProtocol`.
    var requestedDebugType: HDebugRequestType? { get }
}

// MARK: - Sending

extension HJRPCTransportRequest {
    /// Sends the request through Harbor. Requests that opted into logging are sent through
    /// `HJRPCDebugRequest`, which conforms to `HDebugRequestProtocol`, so Harbor logs them
    /// with the requested debug type; the others are sent as-is and never logged, matching
    /// Harbor's opt-in logging for REST requests.
    func send() async -> HResponseWithResult<Model> {
        if let requestedDebugType {
            return await HJRPCDebugRequest(base: self, debugType: requestedDebugType).request()
        }
        return await request()
    }
}
