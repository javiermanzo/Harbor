//
//  HJRPCResponse.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

/// Response wrapper for JSON-RPC requests.
public enum HJRPCResponse<Model: Sendable>: Sendable {
    /// The request completed successfully with the parsed result.
    case success(Model)
    /// The request failed with an error.
    case error(HJRPCRequestError)
}

// MARK: - CustomStringConvertible

extension HJRPCResponse: CustomStringConvertible {
    public var description: String {
        switch self {
        case .success(let model):
            return "HJRPCResponse.success(\(model))"
        case .error(let error):
            return "HJRPCResponse.error(\(error.localizedDescription))"
        }
    }
}
