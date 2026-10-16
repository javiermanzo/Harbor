//
//  HTaskDelegateContext.swift
//  Harbor
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation

/// What `HURLSessionDelegate` needs from the task-specific delegate of a task Harbor started:
/// the auth header key to strip on cross-origin redirects, and a way to report a rejected TLS
/// handshake back to the operation that owns the task. Adopted by `HTaskContext` (REST) and
/// by the WebSocket task delegate of `HarborWebSocket`.
package protocol HTaskDelegateContext: AnyObject, Sendable {
    /// The header key the auth provider set on the request, if any.
    var authHeaderKey: String? { get }

    /// Records that a TLS challenge for the task was rejected.
    func recordTrustFailure()
}
