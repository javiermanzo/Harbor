//
//  HRequestSource.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - Request Source
/// Where `requestStream(source:)` reads from.
public enum HRequestSource: Sendable {
    /// Only the network: yields the remote response.
    case remoteOnly
    /// Only the cache, without a network request: yields the cached response, or throws
    /// `HRequestError.noCachedDataFound`.
    case cacheOnly
    /// The cache, then the network: yields the cached response first when there is one, then
    /// always the remote response.
    case cacheAndRemote
}
