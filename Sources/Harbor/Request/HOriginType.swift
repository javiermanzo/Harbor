//
//  HOriginType.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - Origin Type
/// Where an element yielded by `requestStream(source:)` came from.
public enum HOriginType: Sendable {
    /// Data came from local cache: a cached element yielded before the network answered, or a cached copy
    /// that stood in for the network when it could not answer (offline, or `stale-if-error`).
    case cache
    /// Data came from remote server.
    case remote
}
