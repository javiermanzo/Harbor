//
//  HImageFlight.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// A load shared by every caller asking for the same image at the same time (deduplication).
/// Each caller subscribes and waits; a caller that is cancelled stops waiting at once with the
/// `cancelled` response, and the load itself is only cancelled when its last subscriber leaves.
final class HImageFlight<Response: Sendable>: Sendable {
    /// A subscribed caller.
    private struct Subscriber: Sendable {
        /// The suspended caller, once it waits.
        var continuation: CheckedContinuation<Response, Never>?
        /// Receives the progress and retry events of the load.
        var sink: HImageEventSink?
    }

    /// The mutable state of the flight.
    private struct State: Sendable {
        /// The subscribed callers, by id.
        var subscribers: [UInt64: Subscriber] = [:]
        /// The next subscriber id.
        var nextID: UInt64 = 0
        /// Callers that left before they started waiting.
        var leftBeforeWaiting: Set<UInt64> = []
        /// The response, once the load finished.
        var response: Response?
        /// The task running the load.
        var task: Task<Void, Never>?
        /// Whether every subscriber left and the load was cancelled.
        var isAbandoned = false
    }

    /// The state, shared with cancellation handlers that run on any thread.
    private let state = HLockedState(State())
    /// What a cancelled caller receives.
    private let cancelledResponse: Response

    /// Creates a flight.
    /// - Parameter cancelledResponse: What a cancelled caller receives.
    init(cancelledResponse: Response) {
        self.cancelledResponse = cancelledResponse
    }
}

// MARK: - Subscribing

extension HImageFlight {
    /// Whether every subscriber left: a new caller must start another load.
    var isAbandoned: Bool {
        state.withLock { $0.isAbandoned }
    }

    /// Sets the task running the load, cancelled when the last subscriber leaves.
    /// - Parameter task: The task.
    func attach(_ task: Task<Void, Never>) {
        let cancelNow = state.withLock { state -> Bool in
            state.task = task
            return state.isAbandoned
        }
        if cancelNow { task.cancel() }
    }

    /// Subscribes a caller.
    /// - Parameter sink: Receives the progress and retry events of the load.
    /// - Returns: The subscriber id, or `nil` when the flight was abandoned.
    func subscribe(sink: HImageEventSink?) -> UInt64? {
        state.withLock { state in
            guard !state.isAbandoned else { return nil }
            let id = state.nextID
            state.nextID &+= 1
            state.subscribers[id] = Subscriber(sink: sink)
            return id
        }
    }

    /// Waits for the response; returns the cancelled response as soon as the calling task is cancelled.
    /// - Parameter id: The subscriber id.
    func wait(id: UInt64) async -> Response {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Response, Never>) in
                let immediate = state.withLock { state -> Response? in
                    if let response = state.response { return response }
                    if state.leftBeforeWaiting.remove(id) != nil { return cancelledResponse }
                    state.subscribers[id]?.continuation = continuation
                    return nil
                }
                if let immediate {
                    continuation.resume(returning: immediate)
                }
            }
        } onCancel: {
            leave(id: id)
        }
    }

    /// Unsubscribes a caller; the load is cancelled when it was the last one.
    /// - Parameter id: The subscriber id.
    func leave(id: UInt64) {
        let (continuation, task) = state.withLock { state -> (CheckedContinuation<Response, Never>?, Task<Void, Never>?) in
            guard state.response == nil, let subscriber = state.subscribers.removeValue(forKey: id) else {
                return (nil, nil)
            }
            if subscriber.continuation == nil {
                state.leftBeforeWaiting.insert(id)
            }
            guard state.subscribers.isEmpty else { return (subscriber.continuation, nil) }
            state.isAbandoned = true
            return (subscriber.continuation, state.task)
        }
        continuation?.resume(returning: cancelledResponse)
        task?.cancel()
    }
}

// MARK: - Broadcasting

extension HImageFlight {
    /// Sends an event to every subscriber.
    /// - Parameter event: The event.
    func broadcast(_ event: HImageEvent) {
        let sinks = state.withLock { $0.subscribers.values.compactMap(\.sink) }
        sinks.forEach { $0(event) }
    }

    /// Resumes every subscriber with the response.
    /// - Parameter response: The response.
    func finish(_ response: Response) {
        let continuations = state.withLock { state -> [CheckedContinuation<Response, Never>] in
            state.response = response
            let waiting = state.subscribers.values.compactMap(\.continuation)
            state.subscribers.removeAll()
            return waiting
        }
        continuations.forEach { $0.resume(returning: response) }
    }
}

/// Receives the events of a load; called from any thread, so it must not block.
typealias HImageEventSink = @Sendable (HImageEvent) -> Void
