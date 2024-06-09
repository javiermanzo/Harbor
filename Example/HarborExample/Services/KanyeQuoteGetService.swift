//
//  KanyeQuoteGetService.swift
//  HarborExample
//
//  Created by Javier Manzo on 21/02/2023.
//

import Foundation
import Harbor

class KanyeQuoteGetService: HServiceProtocolWithResult {
    typealias Model = KanyeQuote

    var url: String = "https://api.kanye.rest/"

    var httpMethod: HHttpMethod = .get

    var headers: [String : String]?

    var queryParameters: [String : String]? = nil

    var pathParameters: [String : String]? = nil

    var body: [String : Any]? = nil

    var needAuth: Bool = false

    var timeout: TimeInterval = 5

    init() {

    }
}
