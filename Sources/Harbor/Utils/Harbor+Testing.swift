//
//  Harbor+Testing.swift
//  Harbor
//

import Foundation

extension Harbor {
    /// Internal testing hook for intercepting network requests without configuring a `customURLSession`.
    /// - Parameter protocolClasses: Array of custom `URLProtocol` classes to inject into the session.
    @HRequestManagerActor
    static func setProtocolClasses(_ protocolClasses: [AnyClass]?) {
        HConfig.shared.protocolClasses = protocolClasses
        HRequestManager.invalidateURLSession()
    }
}

