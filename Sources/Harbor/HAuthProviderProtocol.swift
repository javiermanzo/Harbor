//
//  HAuthProviderProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

public protocol HAuthProviderProtocol: Sendable {
    func getAuthorizationHeader() async -> HAuthorizationHeader
    func authFailed() async
}

public struct HAuthorizationHeader: Sendable, Equatable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}
