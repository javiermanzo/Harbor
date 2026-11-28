//
//  HImageEventRelay.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// Delivers the events of one caller to its `onEvent` callback on the main actor, in the order
/// they were sent. After `cancel()` nothing else is delivered, not even events already queued.
final class HImageEventRelay: Sendable {
    /// The queue of events.
    private let continuation: AsyncStream<HImageEvent>.Continuation
    /// The main-actor task calling the handler.
    private let consumer: Task<Void, Never>
    /// Whether the caller was cancelled.
    private let isCancelled: HLockedState<Bool>

    /// Creates a relay.
    /// - Parameter handler: The caller's callback.
    init(handler: @escaping HImageEventHandler) {
        let (stream, continuation) = AsyncStream<HImageEvent>.makeStream()
        let isCancelled = HLockedState(false)
        self.continuation = continuation
        self.isCancelled = isCancelled
        self.consumer = Task { @MainActor in
            for await event in stream where !isCancelled.withLock({ $0 }) {
                handler(event)
            }
        }
    }
}

// MARK: - Delivery

extension HImageEventRelay {
    /// The sink to hand to the loader.
    var sink: HImageEventSink {
        { [continuation] event in continuation.yield(event) }
    }

    /// Drops every event not delivered yet, and any later one.
    func cancel() {
        isCancelled.withLock { $0 = true }
        continuation.finish()
    }

    /// Waits until every queued event was delivered.
    func drain() async {
        continuation.finish()
        await consumer.value
    }
}
