//
//  KanyeQuoteGetRequest.swift
//  HarborExample
//
//  Created by Javier Manzo on 21/02/2023.
//

import Foundation
import Harbor

struct KanyeQuoteGetRequest: HGetRequestProtocol {
    typealias Model = KanyeQuote
    let url: String = "https://api.kanye.rest/"
    var headerParameters: [String: String]?
    let queryParameters: [String: String]? = nil
    let pathParameters: [String: String]? = nil
    let needsAuth: Bool = false
    let timeout: TimeInterval = 5
}
