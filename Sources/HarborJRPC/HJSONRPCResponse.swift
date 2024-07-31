//
//  HJSONRPCResponse.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation

struct HJSONRPCResponse<Model: Codable>: Codable {
    let id: String?
    let result: Model?
    let error: HJSONRPCError?
}

public struct HJSONRPCError: Codable, Sendable {
    let code: Int
    let message: String
    let data: String?
}
