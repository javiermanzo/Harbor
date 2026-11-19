//
//  HarborJRPCImportTests.swift
//  HarborJRPCTests
//
//  Created by Javier Manzo on 23/10/2026.
//

import XCTest
// Only HarborJRPC: this file compiles only while HarborJRPC re-exports Harbor and HarborCore.
import HarborJRPC

/// A request that uses the shared types (`HRetryPolicy`, `HDebugRequestProtocol`) with
/// nothing but `import HarborJRPC`.
private struct ImportProbeRequest: HJRPCRequestProtocol, HDebugRequestProtocol {
    typealias Model = String
    let method = "eth_blockNumber"
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 1, retryNonIdempotentRequests: true)
    let debugType: HDebugRequestType = .none
}

final class HarborJRPCImportTests: XCTestCase {

    func testImportingHarborJRPCExposesTheSharedConfiguration() async {
        // Given only `import HarborJRPC`
        let request = ImportProbeRequest()

        // Then the shared types and the `Harbor` configuration are in scope
        XCTAssertEqual(request.retryPolicy?.maxRetries, 1)
        await Harbor.setDefaultTimeoutInterval(15)
    }
}
