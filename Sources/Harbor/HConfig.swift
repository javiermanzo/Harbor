//
//  HConfig.swift
//
//
//  Created by Javier Manzo on 11/06/2024.
//

import Foundation

struct HConfig: Sendable {
    var authProvider: HAuthProviderProtocol?
    var defaultHeaderParameters: [String: String]?
    var mTLS: HmTLS?
    var sslPinningSHA256: String?
}
