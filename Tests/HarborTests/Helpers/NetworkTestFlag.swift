//
//  NetworkTestFlag.swift
//

import XCTest

/// Guards tests that exercise real network endpoints. These are skipped by default so the
/// suite runs offline; set the `HARBOR_RUN_NETWORK_TESTS` environment variable to `1` to run them.
enum NetworkTestFlag {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["HARBOR_RUN_NETWORK_TESTS"] == "1"
    }

    /// Throws an `XCTSkip` unless network tests are enabled.
    static func skipUnlessEnabled() throws {
        try XCTSkipUnless(isEnabled, "Network tests are disabled. Set HARBOR_RUN_NETWORK_TESTS=1 to run them.")
    }
}
