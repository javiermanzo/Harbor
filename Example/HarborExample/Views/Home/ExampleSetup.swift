//
//  ExampleSetup.swift
//  HarborExample
//
//  One-time Harbor configuration of the demo app
//

import Foundation
import Harbor
import HarborJRPC
import LogBird

@MainActor
enum ExampleSetup {
    private static let logger = LogBird(subsystem: "com.harbor.example", category: "ExampleSetup")

    /// Survives view re-creation: Harbor is configured once per launch.
    private static var isConfigured = false

    static func configureOnce() async {
        guard !isConfigured else { return }
        isConfigured = true

        // Set default headers for all requests
        await Harbor.setDefaultHeaderParameters([
            "X-Client-Version": "1.0.0",
            "X-Client-Platform": "iOS"
        ])

        // Set default cache type (the settings sheet starts on `.urlCache()`)
        await Harbor.setDefaultCacheType(.urlCache())

        // Enable debug logging (the settings sheet starts with logging on)
        await Harbor.setLoggingEnabled(true)

        // Configure JRpc
        await HarborJRPC.configure(url: URL(string: "https://ethereum.publicnode.com")!)

        // mTLS is configured on demand by the "GET - With mTLS" demo.
        logger.log("Harbor configured", level: .info)
    }
}
