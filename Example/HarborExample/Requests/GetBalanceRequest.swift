//
//  GetBalanceRequest.swift
//  HarborExample
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import HarborJRPC

struct GetBalanceRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "eth_getBalance"
    let parameters: HJRPCParams?

    init(address: String) {
        self.parameters = .named(["address": address, "block": "latest"])
    }
}
