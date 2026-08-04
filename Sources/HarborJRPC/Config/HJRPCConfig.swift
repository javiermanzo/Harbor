//
//  HJRPCConfig.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation

/// Configuration for the HarborJRPC module.
public struct HJRPCConfig: Sendable {
    /// The base URL of the JSON-RPC endpoint.
    public var url: String
    /// The JSON-RPC protocol version sent in every request.
    public var jrpcVersion: String

    /// Creates a new configuration.
    /// - Parameters:
    ///   - url: The base URL of the JSON-RPC endpoint.
    ///   - jrpcVersion: The JSON-RPC protocol version (default: "2.0").
    public init(url: String = "", jrpcVersion: String = "2.0") {
        self.url = url
        self.jrpcVersion = jrpcVersion
    }
}
