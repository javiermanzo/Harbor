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
    /// The HTTP status code of the response that carried the error, when it was not a 2xx
    /// (e.g. a server answering `500` with a JSON-RPC error body). `nil` for errors delivered
    /// in a 2xx response. Not part of the JSON-RPC error object, so it is never encoded.
    public internal(set) var httpStatusCode: Int?

    /// The members of a JSON-RPC error object. `httpStatusCode` is not one of them.
    private enum CodingKeys: String, CodingKey {
        /// The `code` member.
        case code
        /// The `message` member.
        case message
        /// The `data` member.
        case data
    }

    /// Creates a new JSON-RPC error.
    /// - Parameters:
    ///   - code: The error code.
    ///   - message: The error message.
    ///   - data: Additional information about the error.
    ///   - httpStatusCode: The non-2xx HTTP status code of the response that carried the error.
    public init(code: Int, message: String, data: HJSONValue? = nil, httpStatusCode: Int? = nil) {
        self.code = code
        self.message = message
        self.data = data
        self.httpStatusCode = httpStatusCode
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
