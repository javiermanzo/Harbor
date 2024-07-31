//
//  JRPCRequest.swift
//  HarborExample
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import HarborJRPC
import Harbor

struct JRPCRequest: HJRPCRequestProtocol, HDebugRequestProtocol {
    var debugType: HDebugRequestType = .requestAndResponse

    typealias Model = String
    var method: String = "eth_blockNumber"
    var needsAuth: Bool = false
    var headers: [String : String]? = nil
    var parameters: [String : Any]? = nil
}
