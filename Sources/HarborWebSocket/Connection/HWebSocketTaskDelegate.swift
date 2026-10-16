//
//  HWebSocketTaskDelegate.swift
//  HarborWebSocket
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation
import Harbor

/// Per-task delegate of every WebSocket task Harbor starts. It is installed as the
/// task-specific delegate (`URLSessionTask.delegate`), so the session's own
/// `HURLSessionDelegate` keeps handling TLS challenges and redirects, while this object:
///
/// - turns the handshake outcome (`didOpenWithProtocol` / `didCompleteWithError`) into the
///   result of `waitForOpen()`,
/// - records the close frame received from the server (`didCloseWith`), which `HWebSocket`
///   reads when `receive()` fails after it,
/// - records a rejected TLS challenge, reported by `HURLSessionDelegate` through
///   `HTaskDelegateContext`, so the failure surfaces as `HWebSocketError.certificate`.
final class HWebSocketTaskDelegate: NSObject, Sendable {

    /// A close frame received from the server.
    struct CloseFrame: Sendable {
        /// The close code.
        let code: URLSessionWebSocketTask.CloseCode
        /// The close reason, if any.
        let reason: Data?
    }

    /// Outcome of the handshake.
    private enum Handshake {
        /// The handshake has not finished.
        case pending
        /// The server accepted the upgrade, selecting the given subprotocol, if any.
        case opened(subprotocol: String?)
        /// The task ended before opening, with the given error.
        case failed(Error)
    }

    /// Mutable state; delegate callbacks arrive on the session's delegate queue, waiters on any executor.
    private struct State {
        /// The handshake outcome.
        var handshake: Handshake = .pending
        /// The task waiting in `waitForOpen()`, if any.
        var openContinuation: CheckedContinuation<String?, Error>?
        /// The close frame received from the server, if any.
        var closeFrame: CloseFrame?
        /// Whether a TLS challenge for the task was rejected.
        var trustEvaluationFailed = false
        /// Whether the task completed (`didCompleteWithError`).
        var isCompleted = false
        /// The tasks waiting in `waitForCompletion()`, keyed so cancellation can remove them.
        var completionWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    }

    /// The header key the auth provider set on the handshake request, if any.
    let authHeaderKey: String?

    /// Lock-protected state.
    private let state = HLockedState(State())

    /// Creates the delegate for one task.
    /// - Parameter authHeaderKey: The header key the auth provider set on the request, if any.
    init(authHeaderKey: String?) {
        self.authHeaderKey = authHeaderKey
    }
}

// MARK: - Handshake

extension HWebSocketTaskDelegate {
    /// Waits for the handshake to complete.
    /// - Returns: The subprotocol the server selected, if any.
    /// - Throws: The error the task completed with before opening.
    func waitForOpen() async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            let settled: Handshake = state.withLock { state in
                switch state.handshake {
                case .pending:
                    state.openContinuation = continuation
                case .opened, .failed:
                    break
                }
                return state.handshake
            }
            switch settled {
            case .pending:
                break
            case .opened(let subprotocol):
                continuation.resume(returning: subprotocol)
            case .failed(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    /// Settles the handshake, resuming a pending waiter at most once.
    /// - Parameter outcome: The handshake outcome.
    private func settle(_ outcome: Handshake) {
        let continuation: CheckedContinuation<String?, Error>? = state.withLock { state in
            guard case .pending = state.handshake else { return nil }
            state.handshake = outcome
            defer { state.openContinuation = nil }
            return state.openContinuation
        }
        switch outcome {
        case .pending:
            break
        case .opened(let subprotocol):
            continuation?.resume(returning: subprotocol)
        case .failed(let error):
            continuation?.resume(throwing: error)
        }
    }

    /// The close frame received from the server, if any.
    var closeFrame: CloseFrame? {
        state.withLock { $0.closeFrame }
    }

    /// Waits until the task completed (`didCompleteWithError`), which `URLSession` reports
    /// after a server close frame (`didCloseWith`). `receive()` can fail before the close
    /// frame is recorded, so `HWebSocket` waits for the completion before deciding whether
    /// the connection closed cleanly or was lost. Returns immediately once completed.
    /// Cancelling the waiting task returns early.
    func waitForCompletion() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resumeNow: Bool = state.withLock { state in
                    guard !state.isCompleted, !Task.isCancelled else { return true }
                    state.completionWaiters[id] = continuation
                    return false
                }
                if resumeNow {
                    continuation.resume()
                }
            }
        } onCancel: {
            let waiter = state.withLock { $0.completionWaiters.removeValue(forKey: id) }
            waiter?.resume()
        }
    }

    /// Records the task completion and resumes the waiters.
    private func markCompleted() {
        let waiters: [CheckedContinuation<Void, Never>] = state.withLock { state in
            state.isCompleted = true
            defer { state.completionWaiters.removeAll() }
            return Array(state.completionWaiters.values)
        }
        waiters.forEach { $0.resume() }
    }

    /// Whether Harbor's delegate rejected a server-trust or client-certificate challenge for the task.
    var trustEvaluationFailed: Bool {
        state.withLock { $0.trustEvaluationFailed }
    }
}

// MARK: - HTaskDelegateContext

extension HWebSocketTaskDelegate: HTaskDelegateContext {
    /// Records that a TLS challenge for the task was rejected.
    func recordTrustFailure() {
        state.withLock { $0.trustEvaluationFailed = true }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension HWebSocketTaskDelegate: URLSessionWebSocketDelegate {
    /// The handshake succeeded.
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        settle(.opened(subprotocol: `protocol`))
    }

    /// The server sent a close frame.
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        state.withLock { $0.closeFrame = CloseFrame(code: closeCode, reason: reason) }
    }

    /// The task ended. Before the handshake completed this means it failed: with the error
    /// `URLSession` reports, or, when a non-101 response ended it without one, with
    /// `URLError.badServerResponse` so the status code can be read from `task.response`.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        settle(.failed(error ?? URLError(.badServerResponse)))
        markCompleted()
    }
}
