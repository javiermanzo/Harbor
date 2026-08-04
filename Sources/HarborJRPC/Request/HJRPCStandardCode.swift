//
//  HJRPCStandardCode.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation

/// Standard error codes defined by the JSON-RPC 2.0 specification.
public enum HJRPCStandardCode: Int, Sendable {
    /// Invalid JSON was received by the server.
    case parseError = -32700
    /// The JSON sent is not a valid request object.
    case invalidRequest = -32600
    /// The method does not exist or is not available.
    case methodNotFound = -32601
    /// Invalid method parameters.
    case invalidParams = -32602
    /// Internal JSON-RPC error.
    case internalError = -32603
}
