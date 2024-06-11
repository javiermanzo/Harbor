//
//  KanyeQuoteGetService.swift
//  HarborExample
//
//  Created by Javier Manzo on 21/02/2023.
//

import Foundation
import Harbor

final class KanyeQuoteGetService: HServiceGetRequestProtocol {
    typealias Model = KanyeQuote

    var url: String = "https://api.kanye.rest/"

    var headerParameters: [String : String]?

    var queryParameters: [String : String]? = nil

    var pathParameters: [String : String]? = nil

    var body: [String : Any]? = nil

    var needsAuth: Bool = false

    var timeout: TimeInterval = 5

    init() { }
}
