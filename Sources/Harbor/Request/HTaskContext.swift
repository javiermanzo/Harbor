//
//  HTaskContext.swift
//  Harbor
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation
import HarborCore

/// Per-task state the REST pipeline attaches to every task it starts, as the task-specific
/// delegate (`URLSession.data(for:delegate:)` and `upload(for:fromFile:delegate:)`). It
/// implements no delegate methods, so it never changes how a session's own delegate handles
/// the task; `HURLSessionDelegate` reads it through `URLSessionTask.delegate` to learn the auth
/// header key to strip on cross-origin redirects and to report a rejected TLS handshake back
/// to the request. WebSocket tasks use `HWebSocketTaskDelegate` instead.
final class HTaskContext: NSObject, Sendable {
    /// The header key the auth provider set on the request, if any.
    let authHeaderKey: String?

    /// Backing storage for `trustEvaluationFailed`; challenge answers arrive on arbitrary queues.
    private let didFailTrustEvaluation = HLockedState(false)

    /// Creates the context for one task.
    /// - Parameter authHeaderKey: The header key the auth provider set on the request, if any.
    init(authHeaderKey: String?) {
        self.authHeaderKey = authHeaderKey
    }

    /// Whether Harbor's delegate rejected a server-trust challenge for the task (a pin
    /// mismatch or an untrusted chain).
    var trustEvaluationFailed: Bool {
        didFailTrustEvaluation.withLock { $0 }
    }
}

// MARK: - HTaskDelegateContext

extension HTaskContext: HTaskDelegateContext {
    /// Records that a TLS challenge for the task was rejected.
    func recordTrustFailure() {
        didFailTrustEvaluation.withLock { $0 = true }
    }
}

// MARK: - URLSessionTaskDelegate

extension HTaskContext: URLSessionTaskDelegate {}
