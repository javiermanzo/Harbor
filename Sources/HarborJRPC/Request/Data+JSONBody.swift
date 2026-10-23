//
//  Data+JSONBody.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation

// MARK: - Response Body Helpers

/// Body inspection helpers for JSON-RPC responses.
extension Data {
    /// Whether the body is empty or contains only JSON whitespace.
    var isBlankJSONBody: Bool {
        allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }
    }
}
