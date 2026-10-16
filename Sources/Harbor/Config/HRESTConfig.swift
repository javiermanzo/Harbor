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
    /// Default JSON decoder used for parsing responses.
    nonisolated static var jsonDecoder: JSONDecoder {
        get { HJSONDecoderStorage.decoder }
        set { HJSONDecoderStorage.decoder = newValue }
    }
}

/// Thread-safe storage for the default JSON decoder used across Harbor.
private enum HJSONDecoderStorage {
    /// The shared decoder, protected by a lock.
    private static let storage = HLockedState(JSONDecoder())
    /// Accessor for the thread-safe JSON decoder instance.
    static var decoder: JSONDecoder {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}
