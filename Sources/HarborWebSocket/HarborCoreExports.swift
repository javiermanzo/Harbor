//
//  HarborCoreExports.swift
//  HarborWebSocket
//
//  Created by Javier Manzo on 16/10/2026.
//

// A WebSocket-only app configures auth, pinning, mTLS and logging through `Harbor.setX(_:)`,
// which lives in HarborCore: re-exporting it makes `import HarborWebSocket` enough, without
// linking Harbor's REST layer.
@_exported import HarborCore
