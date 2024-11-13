//
//  HJRPCResult.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

struct HJRPCResult<Model: HModel>: HModel {
    let id: String?
    let result: Model?
    let error: HJRPCError?
}

public struct HJRPCError: HModel {
    let code: Int
    let message: String
}
