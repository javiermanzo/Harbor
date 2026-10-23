//
//  HarborTestDefaults.swift
//  HarborTests
//
//  Created by Javier Manzo on 23/10/2026.
//

import Foundation
@testable import Harbor
@testable import HarborCore

/// Restores Harbor's global configuration to its defaults. XCTest runs every suite in one
/// process and in no guaranteed order, so a suite that changes the configuration restores it
/// in `tearDown`, and a suite that relies on the defaults restores them in `setUp`.
@HRequestManagerActor
enum HarborTestDefaults {
    /// Mocks on and none registered, no auth provider, default headers or custom session, no
    /// protocol stubs, the `.urlCache()` default cache (emptied), 15 s timeout, no resource
    /// timeout, no pins or mTLS, cookies off and redacted logs.
    static func restore() async {
        Harbor.removeAllMocks()
        Harbor.setMocksEnabled(true)
        Harbor.setAuthProvider(nil)
        Harbor.setDefaultHeaderParameters(nil)
        Harbor.setCustomURLSession(nil)
        Harbor.setProtocolClasses(nil)
        Harbor.setDefaultCacheType(.urlCache())
        Harbor.setDefaultTimeoutInterval(15)
        Harbor.setDefaultResourceTimeoutInterval(nil)
        Harbor.setHTTPShouldHandleCookies(false)
        Harbor.setLogSensitiveValues(false)
        Harbor.setSSLPinningKeys(nil)
        HConfig.shared.sslPinningKeysByHost = nil
        Harbor.clearMTLS()
        await Harbor.clearAllCache()
    }
}
