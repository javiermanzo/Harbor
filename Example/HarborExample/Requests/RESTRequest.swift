//
//  RESTRequest.swift
//  HarborExample
//
//  Created by Javier Manzo on 21/02/2023.
//

import Foundation
import Harbor

struct RESTRequest: HGetRequestProtocol {
    typealias Model = KanyeQuote
    let url: String = "https://api.kanye.rest/"
}
