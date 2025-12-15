//
//  MTLSRequest.swift
//  HarborExample
//
//  Created by Jalil on 15/12/25.
//

import Harbor

struct MTLSRequest: HGetRequestProtocol {
    typealias Model = MtlsModel
    let url: String = "https://certauth.cryptomix.com/json"
}
