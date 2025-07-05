//
//  HarborJRPC.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

/// Main configuration class for the HarborJRPC library.
/// Use this class to configure JSON-RPC settings like base URL and version.
@HRequestManagerActor
public final class HarborJRPC {
    private init() {}

    /// Sets the base URL for all JSON-RPC requests.
    /// - Parameter url: The base URL string (e.g., "https://api.example.com/rpc")
    public static func setURL(_ url: String) {
        HJRPCRequestManager.config.url = url
    }

    /// Sets the JSON-RPC version to use in requests.
    /// - Parameter jrpcVersion: The JSON-RPC version string (default: "2.0")
    public static func setJRPCVersion(_ jrpcVersion: String) {
        HJRPCRequestManager.config.jrpcVersion = jrpcVersion
    }
}
