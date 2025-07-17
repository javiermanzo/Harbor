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
    let code: Int
    /// A human-readable error message.
    let message: String
}
