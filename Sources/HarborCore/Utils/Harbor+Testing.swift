//
//  Harbor+Testing.swift
//  HarborCore
//

import Foundation

// MARK: - Testing

extension Harbor {
    /// Testing hook (`package`, so any test target of this package can call it; apps cannot)
    /// that injects `URLProtocol` classes into the sessions Harbor builds, to stub the network
    /// without a custom session. It does not apply to a session set with `setCustomURLSession(_:)`.
    /// - Parameter protocolClasses: The `URLProtocol` classes to inject, or `nil` for none.
    package static func setProtocolClasses(_ protocolClasses: [AnyClass]?) {
        HConfig.shared.protocolClasses = protocolClasses
        HRequestManager.invalidateURLSession()
    }
}
