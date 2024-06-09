//
//  HAuthProviderProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

public protocol HAuthProviderProtocol {
    func getAuthorizationHeader() async -> HAuthorizationHeader
    func authFailed()
}

public struct HAuthorizationHeader {
    let key: String
    let value: String
}
