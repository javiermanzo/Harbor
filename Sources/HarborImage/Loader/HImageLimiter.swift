//
//  HImageLimiter.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// Limits how many downloads run at once; the others wait in order of arrival.
@HRequestManagerActor
final class HImageLimiter {
    /// The downloads running.
    private var running = 0
    /// The downloads waiting for a slot, in order of arrival.
    private var waiters: [(id: UInt64, continuation: CheckedContinuation<Bool, Never>)] = []
    /// The next waiter id.
    private var nextID: UInt64 = 0
    /// The downloads allowed at once, as of the last `acquire(limit:)`.
    private var limit = 1

    /// Creates a limiter.
    init() {}
}

// MARK: - Slots

extension HImageLimiter {
    /// Waits for a slot. A limit that changed since the last call applies at once: a higher
    /// one starts queued downloads, a lower one holds new ones until enough finish.
    /// - Parameter limit: The downloads allowed at once.
    /// - Returns: `false` when the calling task was cancelled while waiting (no slot is held).
    func acquire(limit: Int) async -> Bool {
        self.limit = max(1, limit)
        resumeWaiters()
        if running < self.limit, waiters.isEmpty {
            running += 1
            return true
        }
        let id = nextID
        nextID &+= 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { @HRequestManagerActor in
                self.cancelWaiter(id: id)
            }
        }
    }

    /// Frees a slot and hands it to the next waiters, as many as the limit allows.
    func release() {
        running = max(0, running - 1)
        resumeWaiters()
    }

    /// Starts waiting downloads, in order of arrival, while there are free slots.
    private func resumeWaiters() {
        while running < limit, !waiters.isEmpty {
            running += 1
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }

    /// Removes a cancelled waiter.
    /// - Parameter id: The waiter id.
    private func cancelWaiter(id: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }
}
