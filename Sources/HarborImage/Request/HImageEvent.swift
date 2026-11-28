//
//  HImageEvent.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// The steps of an image load, delivered to the optional `onEvent` callbacks and to
/// `HarborImage.events(for:)`, always in this order: `started`, any number of `progress` and
/// `retrying`, then `loaded` on success, and `finished` last. `data(for:)` sends no `finished`
/// (the bytes are its return value), and a cancelled caller receives nothing after the
/// cancellation.
public enum HImageEvent: Sendable {
    /// The load started.
    case started
    /// Download progress in `0...1`. Only sent when the server announces the size (`Content-Length`).
    case progress(Double)
    /// Another attempt starts, after a retryable failure or a `401` whose credentials were
    /// refreshed; `attempt` counts them from 1.
    case retrying(attempt: Int)
    /// The image was loaded from the given source.
    case loaded(source: HImageSource)
    /// The load finished.
    case finished(HImageResponse)
}

/// An optional callback receiving the events of a load, run on the main actor.
public typealias HImageEventHandler = @Sendable @MainActor (HImageEvent) -> Void
