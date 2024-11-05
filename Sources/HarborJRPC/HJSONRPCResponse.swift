//
//  HJRPCResult.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation

struct HJRPCResult<Model: Codable & Sendable>: Codable, Sendable {
    let id: String?
    let result: Model?
    let error: HJRPCError?
}

public struct HJRPCError: Codable, Sendable {
    let code: Int
    let message: String
}
