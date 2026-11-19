//
//  HRequestManagerMonitorProtocol.swift
//  HarborCore
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

/// Monitors network connectivity, used internally as a pre-check before executing requests.
///
/// The monitor starts lazily on the first connectivity check. Until it delivers its
/// first path update the real status is unknown, so connectivity is assumed instead
/// of failing requests spuriously. In DEBUG/simulator builds requests are always allowed
/// unless `HConfig.assumeNetworkAvailableInDebug` is disabled.
@HRequestManagerActor
package protocol HRequestManagerMonitorProtocol: Sendable {
    /// Starts the network monitor if it is not already running.
    func start()

    /// Stops the network monitor and resets its state.
    func stop()

    /// Network connectivity check.
    func isConnectedToNetwork() -> Bool
}

// MARK: - Default Implementations

extension HRequestManagerMonitorProtocol {
    /// Default empty implementation for stopping the network monitor.
    func stop() {}
}
