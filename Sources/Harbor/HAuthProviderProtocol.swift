//
//  HAuthProviderProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

public protocol HAuthProviderProtocol {
    func getCredentialsHeader() async -> HAuthCredentialHeader
    func authFailed()
}

public struct HAuthCredentialHeader {
    let key: String
    let value: String
}
