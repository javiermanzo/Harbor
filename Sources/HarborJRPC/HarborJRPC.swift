//
//  HarborJRPC.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

/// Errors that can occur while configuring HarborJRPC.
public enum HJRPCConfigurationError: Error, Sendable {
    /// The provided URL string is not a valid URL.
    case invalidURL(String)
}

// MARK: - LocalizedError

extension HJRPCConfigurationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let urlString):
            return "The URL \"\(urlString)\" is not valid."
        }
    }
}

/// Main configuration class for the HarborJRPC library.
/// Use this class to configure JSON-RPC settings like base URL and version.
@HRequestManagerActor
public final class HarborJRPC {
    private init() {}

    /// Sets the base URL for all JSON-RPC requests.
    /// - Parameter url: The base URL (e.g., `URL(string: "https://api.example.com/rpc")!`)
    public static func setURL(_ url: URL) {
        HJRPCRequestManager.config.url = url.absoluteString
    }

    /// Sets the base URL for all JSON-RPC requests from a string.
    /// - Parameter urlString: The base URL string (e.g., "https://api.example.com/rpc")
    /// - Throws: `HJRPCConfigurationError.invalidURL` if the string is not a valid URL.
    public static func setURL(_ urlString: String) throws {
        guard let url = URL(string: urlString) else {
            throw HJRPCConfigurationError.invalidURL(urlString)
        }
        setURL(url)
    }

    /// Configures the base URL and the JSON-RPC version in a single call.
    ///
    /// Network-level settings (timeout, auth provider, mTLS, mocks, logging) are configured
    /// through `Harbor`'s API, not here.
    /// - Parameters:
    ///   - url: The base URL of the JSON-RPC endpoint.
    ///   - jrpcVersion: The JSON-RPC version string (default: "2.0")
    public static func configure(url: URL, jrpcVersion: String = "2.0") {
        setURL(url)
        setJRPCVersion(jrpcVersion)
    }

    /// Sets the JSON-RPC version to use in requests.
    /// - Parameter jrpcVersion: The JSON-RPC version string (default: "2.0")
    public static func setJRPCVersion(_ jrpcVersion: String) {
        HJRPCRequestManager.config.jrpcVersion = jrpcVersion
    }

    /// Sends several JSON-RPC requests as a single batch call (JSON-RPC 2.0, section 6).
    ///
    /// Notifications included in the batch do not produce a response element.
    /// Servers may reorder or omit responses, so each response is paired with the identifier echoed by the server.
    /// - Parameter requests: The requests to send in the batch.
    /// - Returns: One `HJRPCBatchResponse` per response element returned by the server, or one error per request when the batch itself fails.
    public static func batch(_ requests: [any HJRPCRequestProtocol]) async -> [HJRPCBatchResponse] {
        await HJRPCRequestManager.batch(requests: requests)
    }
}
