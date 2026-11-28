//
//  HarborCoreExports.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

// An image-only app configures auth, pinning, mTLS and logging through `Harbor.setX(_:)`,
// which lives in HarborCore: re-exporting it makes `import HarborImage` enough, without
// linking Harbor's REST layer.
@_exported import HarborCore
