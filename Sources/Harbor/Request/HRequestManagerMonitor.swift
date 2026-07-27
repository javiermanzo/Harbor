//
//  HRequestManagerMonitor.swift
//  Harbor
//
//  Network connectivity monitor used internally as a pre-check before executing requests.
//

import Foundation
import Network

/// Monitors network connectivity, used internally as a pre-check before executing requests.
///
/// The monitor starts lazily on the first connectivity check. Until it delivers its
/// first path update the real status is unknown, so connectivity is assumed instead
/// of failing requests spuriously. In DEBUG/simulator builds requests are always allowed.
@HRequestManagerActor
protocol HRequestManagerMonitorProtocol: Sendable {
    /// Starts the network monitor if it is not already running.
    func start()

    /// Network connectivity check.
    func isConnectedToNetwork() -> Bool
}

/// Default connectivity monitor backed by NWPathMonitor.
@HRequestManagerActor
final class HRequestManagerMonitor: HRequestManagerMonitorProtocol {
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.harbor.networkMonitor")
    private var isMonitorStarted = false
    private var hasReceivedInitialUpdate = false

    /// Starts the network monitor if it is not already running.
    /// Called lazily on the first connectivity check.
    func start() {
        guard !isMonitorStarted else { return }
        isMonitorStarted = true

        monitor.pathUpdateHandler = { _ in
            Task { @HRequestManagerActor in
                self.hasReceivedInitialUpdate = true
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Network connectivity check using NWPathMonitor.
    func isConnectedToNetwork() -> Bool {
        start()

        // Fallback for debug/simulator environments
        #if DEBUG || targetEnvironment(simulator)
        let allowsDebugFallback = true
        #else
        let allowsDebugFallback = false
        #endif

        return Self.shouldAllowRequest(hasReceivedInitialUpdate: hasReceivedInitialUpdate,
                                       pathStatus: monitor.currentPath.status,
                                       allowsDebugFallback: allowsDebugFallback)
    }

    /// Decides whether a request should proceed based on the monitor state.
    /// Until the monitor delivers its first path update the real status is unknown,
    /// so connectivity is assumed instead of failing the request spuriously.
    static func shouldAllowRequest(hasReceivedInitialUpdate: Bool, pathStatus: NWPath.Status, allowsDebugFallback: Bool) -> Bool {
        guard hasReceivedInitialUpdate else { return true }

        if pathStatus == .satisfied {
            return true
        }

        return allowsDebugFallback
    }
}
