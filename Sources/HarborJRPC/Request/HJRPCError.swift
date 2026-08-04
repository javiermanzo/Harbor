//
//  HJRPCError.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

/// Represents a JSON-RPC error returned by the server.
public struct HJRPCError: HModel {
    /// The error code as defined by the JSON-RPC specification.
    public let code: Int
    /// A human-readable error message.
    public let message: String
    /// Additional information about the error, as defined by the server.
    public let data: HJSONValue?

    /// Creates a new JSON-RPC error.
    /// - Parameters:
    ///   - code: The error code.
    ///   - message: The error message.
    ///   - data: Additional information about the error.
    public init(code: Int, message: String, data: HJSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

// MARK: - Standard Codes

public extension HJRPCError {
    /// The matching standard error code, when `code` is one of the codes defined by the JSON-RPC specification.
    var standardCode: HJRPCStandardCode? {
        HJRPCStandardCode(rawValue: code)
    }

    /// Whether `code` is one of the codes defined by the JSON-RPC specification.
    var isStandard: Bool {
        standardCode != nil
    }

    /// Whether `code` is inside the server error range (-32099...-32000) reserved for implementation-defined server errors.
    var isServerError: Bool {
        (-32099 ... -32000).contains(code)
    }
}
