//
//  HJRPCResult.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

struct HJRPCResult<Model: HModel>: HModel {
    let id: String?
    let result: Model?
    let error: HJRPCError?
}

/// Represents a JSON-RPC error returned by the server.
public struct HJRPCError: HModel {
    /// The error code as defined by the JSON-RPC specification.
    public let code: Int
    /// A human-readable error message.
    public let message: String

    /// Creates a new JSON-RPC error.
    /// - Parameters:
    ///   - code: The error code
    ///   - message: The error message
    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}
