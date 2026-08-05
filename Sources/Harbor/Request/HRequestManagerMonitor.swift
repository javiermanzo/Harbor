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
/// of failing requests spuriously. In DEBUG/simulator builds requests are always allowed
/// unless `HConfig.assumeNetworkAvailableInDebug` is disabled.
@HRequestManagerActor
protocol HRequestManagerMonitorProtocol: Sendable {
    /// Starts the network monitor if it is not already running.
    func start()

    /// Stops the network monitor and resets its state.
    func stop()

    /// Network connectivity check.
    func isConnectedToNetwork() -> Bool
}

extension HRequestManagerMonitorProtocol {
    func stop() {}
}

/// Default connectivity monitor backed by NWPathMonitor.
@HRequestManagerActor
final class HRequestManagerMonitor: HRequestManagerMonitorProtocol {
    /// A cancelled NWPathMonitor cannot be restarted, so the instance is recreated on each start.
    private var monitor: NWPathMonitor?
    /// The dispatch queue used by the network monitor.
    private let monitorQueue = DispatchQueue(label: "com.harbor.networkMonitor")
    /// Tracks if the monitor has been started to avoid multiple starts.
    private var isMonitorStarted = false
    /// Tracks if the monitor has received its first path update.
    private var hasReceivedInitialUpdate = false

    /// Starts the network monitor if it is not already running.
    /// Called lazily on the first connectivity check.
    func start() {
        guard !isMonitorStarted else { return }
        isMonitorStarted = true

        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { _ in
            Task { @HRequestManagerActor in
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
