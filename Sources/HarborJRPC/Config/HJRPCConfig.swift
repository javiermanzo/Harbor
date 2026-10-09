//
//  HJRPCConfig.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation

/// Global configuration of the HarborJRPC module, set with `HarborJRPC.configure(url:jrpcVersion:)`.
struct HJRPCConfig: Sendable {
    /// The base URL of the JSON-RPC endpoint.
    var url: String
    /// The JSON-RPC protocol version sent in every request.
    var jrpcVersion: String

    /// Creates a new configuration.
    /// - Parameters:
    ///   - url: The base URL of the JSON-RPC endpoint.
    ///   - jrpcVersion: The JSON-RPC protocol version (default: "2.0").
    init(url: String = "", jrpcVersion: String = "2.0") {
        self.url = url
        self.jrpcVersion = jrpcVersion
    }
}
