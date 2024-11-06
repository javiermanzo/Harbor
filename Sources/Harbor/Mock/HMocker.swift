//
//  HMocker.swift
//  Harbor
//
//  Created by Javier Manzo on 06/11/2024.
//

import Foundation

@HRequestManagerActor
internal final class HMocker: Sendable {
    internal static var mocks: [String: HMock] = [:]

    static func register(mock: HMock) {
        mocks[mock.requestName] = mock
    }

    static func remove(mock: HMock) {
        mocks.removeValue(forKey: mock.requestName)
    }

    static func mock(request: HRequestBaseRequestProtocol) -> HMock? {
        return mocks["\(String(describing: type(of: request)))"]
    }
}
