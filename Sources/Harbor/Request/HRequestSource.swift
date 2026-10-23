//
//  HRequestSource.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import HarborCore

// MARK: - Request Source

/// Where `requestStream(source:)` reads from.
public enum HRequestSource: Sendable {
    /// Only the network: yields the remote response. When the request falls back to a cached
    /// copy (offline, or `stale-if-error`), that copy is yielded instead, tagged `.cache`.
    case remoteOnly
    /// Only the cache, without a network request: yields the cached response, or throws
    /// `HRequestError.noCachedDataFound`.
    case cacheOnly
    /// The cache, then the network: yields the cached response first when there is one, then
    /// the remote response. A remote leg answered by the same cached copy (offline, or
    /// `stale-if-error`) is not yielded twice, and the stream throws when the remote request
    /// fails, even after a cached element.
    case cacheAndRemote
}
