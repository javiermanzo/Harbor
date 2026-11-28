//
//  HImageDownloadDelegate.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// The task-specific delegate of an image download. It collects the body, reports progress,
/// stops the transfer past the size limit, and tells `HURLSessionDelegate` (the session
/// delegate, which still answers the TLS challenges and redirects) the auth header key to strip
/// on cross-origin redirects.
final class HImageDownloadDelegate: NSObject, Sendable {
    /// What a finished download produced.
    struct Completion: Sendable {
        /// The body.
        let data: Data
        /// The response, if one was received.
        let response: HTTPURLResponse?
        /// The transport error, if any.
        let error: Error?
        /// Whether the download was stopped for exceeding the size limit.
        let exceededLimit: Bool
        /// Whether Harbor's delegate rejected a TLS challenge.
        let trustEvaluationFailed: Bool
    }

    /// The mutable state of the download.
    private struct State: Sendable {
        /// The body received so far.
        var data = Data()
        /// The response.
        var response: HTTPURLResponse?
        /// The expected body size, when announced.
        var expectedLength: Int64 = -1
        /// The last progress reported.
        var lastProgress = 0.0
        /// Whether the size limit was exceeded.
        var exceededLimit = false
        /// Whether a TLS challenge was rejected.
        var trustFailed = false
        /// The completion, once the task finished.
        var completion: Completion?
        /// The suspended caller.
        var continuation: CheckedContinuation<Completion, Never>?
    }

    /// The header key the auth provider set on the request, if any.
    let authHeaderKey: String?
    /// The largest body accepted, in bytes.
    private let maxBytes: Int
    /// Receives the download progress.
    private let onProgress: @Sendable (Double) -> Void
    /// The state, updated from the session's delegate queue.
    private let state = HLockedState(State())

    /// Creates the delegate of one download.
    /// - Parameters:
    ///   - authHeaderKey: The header key the auth provider set on the request, if any.
    ///   - maxBytes: The largest body accepted, in bytes.
    ///   - onProgress: Receives the download progress.
    init(authHeaderKey: String?, maxBytes: Int, onProgress: @escaping @Sendable (Double) -> Void) {
        self.authHeaderKey = authHeaderKey
        self.maxBytes = maxBytes
        self.onProgress = onProgress
    }
}

// MARK: - Waiting

extension HImageDownloadDelegate {
    /// Waits for the task to finish.
    func waitForCompletion() async -> Completion {
        await withCheckedContinuation { continuation in
            let completion = state.withLock { state -> Completion? in
                if let completion = state.completion { return completion }
                state.continuation = continuation
                return nil
            }
            if let completion {
                continuation.resume(returning: completion)
            }
        }
    }
}

// MARK: - HTaskDelegateContext

extension HImageDownloadDelegate: HTaskDelegateContext {
    /// Records that a TLS challenge for the task was rejected.
    func recordTrustFailure() {
        state.withLock { $0.trustFailed = true }
    }
}

// MARK: - URLSessionDataDelegate

extension HImageDownloadDelegate: URLSessionDataDelegate {
    /// Rejects a successful response that announces a body above the limit. Other statuses are
    /// let through: their body is not collected, and the status decides what happens next
    /// (the `401` refresh, a retry, `.api`).
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let tooLarge = state.withLock { state -> Bool in
            state.response = response as? HTTPURLResponse
            state.expectedLength = response.expectedContentLength
            guard Self.isSuccess(state.response), response.expectedContentLength > Int64(maxBytes) else { return false }
            state.exceededLimit = true
            return true
        }
        completionHandler(tooLarge ? .cancel : .allow)
    }

    /// Collects the body of a successful response and reports progress; stops the transfer past
    /// the limit. The body of any other status is discarded.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let (exceeded, progress) = state.withLock { state -> (Bool, Double?) in
            guard !state.exceededLimit else { return (true, nil) }
            guard Self.isSuccess(state.response) else { return (false, nil) }
            state.data.append(data)
            if state.data.count > maxBytes {
                state.exceededLimit = true
                state.data = Data()
                return (true, nil)
            }
            guard state.expectedLength > 0 else { return (false, nil) }
            let fraction = min(1, Double(state.data.count) / Double(state.expectedLength))
            guard fraction - state.lastProgress >= 0.01 || (fraction == 1 && state.lastProgress < 1) else { return (false, nil) }
            state.lastProgress = fraction
            return (false, fraction)
        }
        if exceeded {
            dataTask.cancel()
        } else if let progress {
            onProgress(progress)
        }
    }

    /// Records the completion and resumes the caller, outside the lock.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, completion) = state.withLock { state -> (CheckedContinuation<Completion, Never>?, Completion) in
            let completion = Completion(data: state.data,
                                        response: state.response ?? task.response as? HTTPURLResponse,
                                        error: error,
                                        exceededLimit: state.exceededLimit,
                                        trustEvaluationFailed: state.trustFailed)
            state.completion = completion
            defer { state.continuation = nil }
            return (state.continuation, completion)
        }
        continuation?.resume(returning: completion)
    }

    /// Whether the response has a `2xx` status.
    /// - Parameter response: The response, if one was received.
    private static func isSuccess(_ response: HTTPURLResponse?) -> Bool {
        (200...299).contains(response?.statusCode ?? 0)
    }
}
