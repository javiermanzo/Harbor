//
//  HLockedState.swift
//  Harbor
//

import Foundation

/// A value protected by a lock, safe to share across concurrency domains. `Value` must be
/// `Sendable`, since `withLock` hands it (and what it returns) to any thread.
package final class HLockedState<Value: Sendable>: @unchecked Sendable {
    /// Mutex protecting `value`.
    private let lock = NSLock()
    /// The protected value; only accessed while holding `lock`.
    private var value: Value

    /// Creates the box.
    /// - Parameter value: The initial value.
    package init(_ value: Value) {
        self.value = value
    }

    /// Runs `body` with exclusive access to the value.
    /// - Parameter body: The closure reading or mutating the value.
    /// - Returns: The closure's result.
    package func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
