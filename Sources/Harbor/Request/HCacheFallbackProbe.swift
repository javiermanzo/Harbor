import Foundation

/// Records that a request was answered from a cached copy as a fallback (offline, or a failing server with
/// `stale-if-error`) instead of by the network. `requestStream(source:)` reads it to tag such an answer
/// `HOriginType.cache`: it is the device's copy, not the server's word.
final class HCacheFallbackProbe: @unchecked Sendable {
    /// The probe of the stream request running on this task, if any.
    @TaskLocal static var current: HCacheFallbackProbe?

    private let lock = NSLock()
    private var served = false

    /// Whether a cached copy answered in place of the network.
    var wasServedFromCache: Bool {
        lock.lock()
        defer { lock.unlock() }
        return served
    }

    /// Called where the manager returns a cached fallback.
    static func markServedFromCache() {
        guard let probe = current else { return }
        probe.lock.lock()
        probe.served = true
        probe.lock.unlock()
    }

    /// Called when a later attempt is answered by the network after all.
    static func markServedFromNetwork() {
        guard let probe = current else { return }
        probe.lock.lock()
        probe.served = false
        probe.lock.unlock()
    }
}
