//
//  HRESTConfig.swift
//  Harbor
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation
import HarborCore

/// Configuration that only the REST pipeline uses (cache, mocks, response decoding). The state
/// shared by every product (auth, headers, timeouts, security, logging) is `HConfig`.
/// Access is serialized via `@HRequestManagerActor`, like `HConfig`.
@HRequestManagerActor
struct HRESTConfig {
    /// Shared singleton instance of the REST configuration.
    static var shared = HRESTConfig()

    /// Default cache type for requests without explicit cache settings. Default is `.urlCache`.
    var cacheType: HCache.CacheType = .urlCache()
    /// Whether registered mocks answer requests. Default is true in DEBUG builds, false otherwise.
    var mocksEnabled: Bool = HBuild.isDebug
    /// Default JSON decoder used for parsing responses (`parseData(data:model:)`). It is
    /// never reconfigured, and decoding with a shared `JSONDecoder` is thread-safe.
    nonisolated static let jsonDecoder = JSONDecoder()
}
