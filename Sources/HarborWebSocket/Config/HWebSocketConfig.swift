//
//  HWebSocketConfig.swift
//  HarborWebSocket
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation
import Harbor

/// Global configuration of the HarborWebSocket module, set through `HarborWebSocket`.
/// Access is serialized via `@HRequestManagerActor`, like Harbor's own configuration.
@HRequestManagerActor
struct HWebSocketConfig {
    /// Shared singleton instance of the configuration.
    static var shared = HWebSocketConfig()

    /// The keep-alive ping interval used by connections that do not set their own. `nil`
    /// (default) sends no pings.
    var pingInterval: TimeInterval?
}
