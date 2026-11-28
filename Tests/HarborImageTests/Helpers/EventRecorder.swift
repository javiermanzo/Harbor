//
//  EventRecorder.swift
//  HarborImageTests
//
//  Records the events a load delivers to its callback, for the loader and callback tests.
//

import Foundation
@testable import HarborCore
@testable import HarborImage

/// Records the events of a load; safe to append to from the main actor and read from the tests.
final class EventRecorder: Sendable {
    /// The events, in delivery order.
    private let events = HLockedState([HImageEvent]())

    /// Records an event.
    func append(_ event: HImageEvent) {
        events.withLock { $0.append(event) }
    }

    /// The events recorded so far.
    var all: [HImageEvent] {
        events.withLock { $0 }
    }

    /// A compact name per event: `started`, `progress`, `retrying(n)`, `loaded(source)`,
    /// `finished(success)` or `finished(failure)`.
    var names: [String] {
        all.map { event in
            switch event {
            case .started: return "started"
            case .progress: return "progress"
            case .retrying(let attempt): return "retrying(\(attempt))"
            case .loaded(let source): return "loaded(\(source.rawValue))"
            case .finished(let response): return response.result != nil ? "finished(success)" : "finished(failure)"
            }
        }
    }
}
