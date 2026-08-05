//
//  HarborConnectivityTests.swift
//  Harbor
//
//  Tests for the network connectivity pre-check (NWPathMonitor based).
//

import XCTest
import Network
@testable import Harbor

@HRequestManagerActor
final class HarborConnectivityTests: XCTestCase {

    // MARK: - shouldAllowRequest decision logic

    func testShouldAllowRequestBeforeInitialUpdate() async {
        // Given the monitor has not delivered its first path update yet (status unknown),
        // requests must proceed optimistically even without the debug fallback.
        // Regression test: previously the first request after launch was rejected
        // with .noConnection in Release builds.
        let allowed = HRequestManagerMonitor.shouldAllowRequest(hasReceivedInitialUpdate: false,
                                                         pathStatus: .unsatisfied,
                                                         allowsDebugFallback: false)

        XCTAssertTrue(allowed)
    }

    func testShouldAllowRequestWhenPathIsSatisfied() async {
        let allowed = HRequestManagerMonitor.shouldAllowRequest(hasReceivedInitialUpdate: true,
                                                         pathStatus: .satisfied,
                                                         allowsDebugFallback: false)

        XCTAssertTrue(allowed)
    }

    func testShouldBlockRequestWhenOfflineInRelease() async {
        // Given a real offline reading after the initial update,
        // requests must still be blocked when there is no debug fallback (Release).
        let allowed = HRequestManagerMonitor.shouldAllowRequest(hasReceivedInitialUpdate: true,
                                                         pathStatus: .unsatisfied,
                                                         allowsDebugFallback: false)

        XCTAssertFalse(allowed)
    }

    func testShouldAllowRequestWhenOfflineWithDebugFallback() async {
        // Given a real offline reading, DEBUG/simulator builds keep the permissive fallback.
        let allowed = HRequestManagerMonitor.shouldAllowRequest(hasReceivedInitialUpdate: true,
                                                         pathStatus: .unsatisfied,
                                                         allowsDebugFallback: true)

        XCTAssertTrue(allowed)
    }

    func testShouldBlockRequestWhenRequiresConnectionInRelease() async {
        // .requiresConnection keeps the previous behavior: treated as offline in Release.
        let allowed = HRequestManagerMonitor.shouldAllowRequest(hasReceivedInitialUpdate: true,
                                                         pathStatus: .requiresConnection,
                                                         allowsDebugFallback: false)

        XCTAssertFalse(allowed)
    }

    // MARK: - Integration

    func testIsConnectedToNetworkReturnsTrueInDebug() async {
        // In DEBUG the check always allows requests (fallback), starting the monitor lazily.
        XCTAssertTrue(HRequestManager.connectivityMonitor.isConnectedToNetwork())
    }

    func testStartNetworkMonitorIsIdempotent() async {
        // Starting the monitor multiple times must be safe.
        HRequestManager.connectivityMonitor.start()
        HRequestManager.connectivityMonitor.start()

        XCTAssertTrue(HRequestManager.connectivityMonitor.isConnectedToNetwork())
    }

    func testStopNetworkMonitorAllowsRestart() async {
        // Stopping the monitor must leave it in a state where the next check starts it fresh.
        HRequestManager.connectivityMonitor = HRequestManagerMonitor()
        HRequestManager.connectivityMonitor.start()

        await Harbor.stopNetworkMonitor()

        XCTAssertTrue(HRequestManager.connectivityMonitor.isConnectedToNetwork())
    }

    func testRequestFailsWithNoConnectionWhenMonitorReportsOffline() async {
        // Given a fake monitor that reports offline (bypasses the DEBUG fallback),
        // the request pipeline must short-circuit with .noConnection without hitting the network.
        HRequestManager.connectivityMonitor = FakeConnectivityMonitor(connected: false)
        defer { HRequestManager.connectivityMonitor = HRequestManagerMonitor() }

        await Harbor.removeAllMocks()
        let response = await MockGetRequest<MockModel>(url: "https://example.com/users").request()

        guard case .error(let error) = response, case .noConnection = error else {
            XCTFail("Expected .noConnection but got: \(response)")
            return
        }
    }
}

/// Fake connectivity monitor for tests: reports a fixed connectivity state.
@HRequestManagerActor
final class FakeConnectivityMonitor: HRequestManagerMonitorProtocol {
    private let connected: Bool

    init(connected: Bool) {
        self.connected = connected
    }

    func start() {}

    func isConnectedToNetwork() -> Bool {
        connected
    }
}
