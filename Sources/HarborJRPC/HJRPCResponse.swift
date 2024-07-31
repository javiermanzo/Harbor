//
//  File.swift
//  
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

public enum HJRPCResponse<Model: Sendable>: Sendable {
    case success(Model)
    case cancelled
    case error(HJRPCRequestError)
}
