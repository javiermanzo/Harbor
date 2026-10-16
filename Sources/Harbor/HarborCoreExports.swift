//
//  HarborCoreExports.swift
//  Harbor
//
//  Created by Javier Manzo on 16/10/2026.
//

// The shared types and configuration live in HarborCore (an implementation module that is not a
// product). Re-exporting it keeps `import Harbor` giving access to `HRetryPolicy`,
// `HRequestError`, `Harbor.setAuthProvider(_:)` and the rest, exactly as when they were declared here.
@_exported import HarborCore
