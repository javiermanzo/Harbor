//
//  HRequestManagerMonitor.swift
//  Harbor
//
//  Network connectivity monitor used internally as a pre-check before executing requests.
//

import Foundation
import Network

/// Default connectivity monitor backed by NWPathMonitor.
@HRequestManagerActor
final class HRequestManagerMonitor {
    /// A cancelled NWPathMonitor cannot be restarted, so the instance is recreated on each start.
    private var monitor: NWPathMonitor?
    /// The dispatch queue used by the network monitor.
    private let monitorQueue = DispatchQueue(label: "com.harbor.networkMonitor")
    /// Tracks if the monitor has been started to avoid multiple starts.
    private var isMonitorStarted = false
    /// Tracks if the monitor has received its first path update.
    private var hasReceivedInitialUpdate = false
}

// MARK: - HRequestManagerMonitorProtocol

extension HRequestManagerMonitor: HRequestManagerMonitorProtocol {
    /// Starts the network monitor if it is not already running.
    /// Called lazily on the first connectivity check.
    func start() {
        guard !isMonitorStarted else { return }
        isMonitorStarted = true

        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { _ in
            Task { @HRequestManagerActor in
                // A late update from a monitor stopped since then must not mark the new one.
                guard self.monitor === monitor else { return }
                self.hasReceivedInitialUpdate = true
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Stops the network monitor and resets its state, so the next check starts it fresh.
    func stop() {
        monitor?.cancel()
        monitor = nil
        isMonitorStarted = false
        hasReceivedInitialUpdate = false
    }

    /// Network connectivity check using NWPathMonitor.
    /// - Returns: `false` only when the path is `.unsatisfied` (and no debug fallback applies), `true` otherwise.
    func isConnectedToNetwork() -> Bool {
        start()

        // Fallback for debug/simulator environments
        #if DEBUG || targetEnvironment(simulator)
        let allowsDebugFallback = HConfig.shared.assumeNetworkAvailableInDebug
        #else
        let allowsDebugFallback = false
        #endif

        return Self.shouldAllowRequest(hasReceivedInitialUpdate: hasReceivedInitialUpdate,
                                       pathStatus: monitor?.currentPath.status ?? .satisfied,
                                       allowsDebugFallback: allowsDebugFallback)
    }
}

// MARK: - Request Gating

extension HRequestManagerMonitor {
    /// Decides whether a request should proceed based on the monitor state.
    /// - Parameters:
    ///   - hasReceivedInitialUpdate: Whether the monitor has delivered its first path update.
    ///   - pathStatus: Current status of network path.
    ///   - allowsDebugFallback: Whether debug fallback to assume availability is active.
    /// - Returns: `true` if request execution is permitted, `false` otherwise.
    static func shouldAllowRequest(hasReceivedInitialUpdate: Bool, pathStatus: NWPath.Status, allowsDebugFallback: Bool) -> Bool {
        guard hasReceivedInitialUpdate else { return true }

        // Only a definitive `.unsatisfied` blocks: `.requiresConnection` means a connection
        // can be brought up on demand (e.g. VPN on demand, cellular waking up), which the
        // request itself triggers.
        if pathStatus != .unsatisfied {
            return true
        }

        return allowsDebugFallback
    }
}
