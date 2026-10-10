//
//  HRequestWithEmptyResponseProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - Request with Empty Result Protocol
/// A request whose response body is not decoded: it reports success or an `HRequestError`.
public protocol HRequestWithEmptyResponseProtocol: HRequestBaseRequestProtocol {
    /// Sends the request. Never throws: failures are returned as `.error`. Cancelling the
    /// calling `Task` cancels the request (`.error(.cancelled)`).
    /// - Returns: `.success` for a 2xx response, or `.error` with the reason it failed.
    func request() async -> HResponse
}

/// Default implementation for `HRequestWithEmptyResponseProtocol`.
public extension HRequestWithEmptyResponseProtocol {
    /// Default implementation that routes through `HRequestManager`.
    func request() async -> HResponse {
        return await HRequestManager.request(request: self)
    }
}
