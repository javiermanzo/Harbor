//
//  HCacheFallbackProbe.swift
//  Harbor
//

import Foundation

/// Records that a request was answered from a cached copy as a fallback (offline, or a failing server with
/// `stale-if-error`) instead of by the network. `requestStream(source:)` reads it to tag such an answer
/// `HOriginType.cache`: it is the device's copy, not the server's word.
final class HCacheFallbackProbe: Sendable {
    /// The probe of the stream request running on this task, if any.
    @TaskLocal static var current: HCacheFallbackProbe?

    /// Whether the last answer came from a cached fallback; read and written from arbitrary tasks.
    private let served = HLockedState(false)

    /// Whether a cached copy answered in place of the network.
    var wasServedFromCache: Bool {
        served.withLock { $0 }
    }

    /// Called where the manager returns a cached fallback.
    static func markServedFromCache() {
        current?.served.withLock { $0 = true }
    }

    /// Called when a later attempt is answered by the network after all.
    static func markServedFromNetwork() {
        current?.served.withLock { $0 = false }
    }
}
