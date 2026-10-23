//
//  HarborExports.swift
//  HarborJRPC
//
//  Created by Javier Manzo on 23/10/2026.
//

// A JSON-RPC call is a REST POST, so HarborJRPC's API is built on Harbor's: `HRetryPolicy`,
// `HDebugRequestProtocol`, `Harbor.setAuthProvider(_:)` and the rest of the shared
// configuration. Re-exporting Harbor (which re-exports HarborCore) makes `import HarborJRPC`
// enough, as `import Harbor` and `import HarborWebSocket` are.
@_exported import Harbor
