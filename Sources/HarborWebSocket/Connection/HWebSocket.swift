//
//  HWebSocket.swift
//  HarborWebSocket
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation
import HarborCore

/// An open WebSocket connection, returned by `HWebSocketRequestProtocol.connect()`.
///
/// Messages from the server arrive through `messages`; `send` writes text, binary or JSON
/// messages; `close(code:reason:)` ends the connection. The connection is an actor: every
/// call is `async`, and `state` tells whether it is still open.
///
/// ```swift
/// let socket = try await ChatSocket().connect()
/// try await socket.send(json: ["room": "swift"])
///
/// do {
///     for try await message in socket.messages {
///         let event = try message.decode(ChatEvent.self)
///         print(event)
///     }
///     // The loop ended because the connection closed; `state` carries the close code.
/// } catch {
///     // The connection was lost, or the loop left through `throw`: close it explicitly.
///     await socket.close()
/// }
/// ```
///
/// Lifecycle:
/// - `messages` **finishes** when the connection closes through a close frame, sent by the
///   server or by `close(code:reason:)`. `state` is then `.closed` with that code.
/// - `messages` **throws** an `HWebSocketError` when the connection is lost without a close
///   frame: a transport failure, a keep-alive ping without pong (`.pingTimeout`) or a message
///   larger than `maximumMessageSize` (`.messageTooBig`). `state` is then
///   `.closed(code: .abnormalClosure, reason: nil)`.
/// - Cancelling the task that iterates `messages` closes the connection with `.goingAway`.
///   Leaving the loop any other way (`break`, `return`, a `throw` of your own) does not:
///   call `close(code:reason:)`.
/// - Messages are read continuously and buffered until iterated, so close frames and pings
///   are handled even while the app is not reading. Iterate `messages` from one place.
/// - A connection that is no longer needed must be closed with `close(code:reason:)`: like a
///   `URLSessionTask`, it stays open (and the `HWebSocket` alive) until then.
public actor HWebSocket {

    /// The messages received from the server, in order. See the type documentation for when
    /// the stream finishes or throws. Iterate it from one place: `AsyncThrowingStream` hands
    /// each message to a single consumer.
    public nonisolated let messages: AsyncThrowingStream<HWebSocketMessage, Error>

    /// The subprotocol the server selected among the request's `subprotocols`, or `nil` when
    /// none was negotiated.
    public nonisolated let negotiatedSubprotocol: String?

    /// Whether the connection is open or closed, and how it closed.
    public private(set) var state: HWebSocketState = .open

    /// The underlying task.
    private let task: URLSessionWebSocketTask
    /// The leased session the task runs on; released when the connection closes.
    private let session: URLSession
    /// The task delegate, which records the server's close frame and TLS rejections.
    private let delegate: HWebSocketTaskDelegate
    /// The continuation feeding `messages`.
    private let continuation: AsyncThrowingStream<HWebSocketMessage, Error>.Continuation
    /// The keep-alive ping interval, or `nil` for no pings.
    private let pingInterval: TimeInterval?
    /// Debug logging, when the request opted in.
    private let logContext: HWebSocketLogContext?
    /// The loop reading messages from the task.
    private var receiveTask: Task<Void, Never>?
    /// The keep-alive ping loop.
    private var pingTask: Task<Void, Never>?

    /// Creates the connection object for an open task. Call `start()` to begin reading.
    /// - Parameters:
    ///   - task: The open WebSocket task.
    ///   - session: The leased session the task runs on.
    ///   - delegate: The task delegate.
    ///   - negotiatedSubprotocol: The subprotocol the server selected.
    ///   - pingInterval: The keep-alive ping interval, or `nil`. Values that are not finite
    ///     and positive disable the pings.
    ///   - logContext: Debug logging, when the request opted in.
    init(task: URLSessionWebSocketTask,
         session: URLSession,
         delegate: HWebSocketTaskDelegate,
         negotiatedSubprotocol: String?,
         pingInterval: TimeInterval?,
         logContext: HWebSocketLogContext?) {
        self.task = task
        self.session = session
        self.delegate = delegate
        self.negotiatedSubprotocol = negotiatedSubprotocol
        self.pingInterval = pingInterval.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.logContext = logContext
        (messages, continuation) = AsyncThrowingStream.makeStream(of: HWebSocketMessage.self, bufferingPolicy: .unbounded)
    }
}

// MARK: - Sending

public extension HWebSocket {
    /// Sends a text message.
    /// - Parameter text: The text to send.
    /// - Throws: `.notConnected` when the connection is closed, or the transport error.
    func send(_ text: String) async throws(HWebSocketError) {
        try await send(message: .text(text))
    }

    /// Sends a binary message.
    /// - Parameter data: The bytes to send.
    /// - Throws: `.notConnected` when the connection is closed, or the transport error.
    func send(_ data: Data) async throws(HWebSocketError) {
        try await send(message: .data(data))
    }

    /// Encodes a value as JSON and sends it as a text message.
    /// - Parameters:
    ///   - value: The value to encode.
    ///   - encoder: The encoder to use. Default: a new `JSONEncoder`.
    /// - Throws: `.codable` when the value cannot be encoded, `.notConnected` when the
    ///   connection is closed, or the transport error.
    func send<T: Encodable & Sendable>(json value: T, encoder: JSONEncoder = JSONEncoder()) async throws(HWebSocketError) {
        let text: String
        do {
            let data = try encoder.encode(value)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "The encoded JSON is not valid UTF-8"))
            }
            text = encoded
        } catch {
            throw .codable(modelName: "\(T.self)", error: error)
        }
        try await send(message: .text(text))
    }

    /// Sends a ping frame and waits for the server's pong, for at most the request's
    /// `pingInterval` (10 seconds when none is set). A pong that does
    /// not arrive in time means the connection is dead: it is closed, `messages` throws
    /// `.pingTimeout` and so does this call.
    /// - Throws: `.notConnected` when the connection is closed, `.pingTimeout` when the pong
    ///   did not arrive in time, `.cancelled` when the calling task was cancelled (the
    ///   connection stays open), or the transport error.
    func ping() async throws(HWebSocketError) {
        guard case .open = state else { throw .notConnected }
        let outcome = await Self.ping(task, timeout: pingInterval ?? Self.defaultPingTimeout)
        // A caller that was cancelled while waiting did not observe a dead link: cancelling it
        // must neither close a healthy connection nor report a timeout.
        guard !Task.isCancelled else { throw .cancelled }
        switch outcome {
        case .pong:
            return
        case .failed(let error):
            throw mapped(error)
        case .timedOut:
            await pingTimedOut()
            throw .pingTimeout
        }
    }

    /// Closes the connection: sends a close frame with the given code and reason, finishes
    /// `messages` and sets `state`. Calling it on a closed connection does nothing.
    /// - Parameters:
    ///   - code: The close code to send. Default: `.normalClosure`.
    ///   - reason: An optional reason sent with the close frame.
    func close(code: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: Data? = nil) async {
        guard case .open = state else { return }
        task.cancel(with: code, reason: reason)
        await finish(code: code, reason: reason, error: nil, initiatedLocally: true)
    }

}

// MARK: - Lifecycle

extension HWebSocket {
    /// Starts the receive loop and, when configured, the keep-alive ping loop. Cancelling the
    /// task that iterates `messages` closes the connection.
    func start() {
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination, let self else { return }
            Task { await self.close(code: .goingAway) }
        }

        receiveTask = Task { [task, continuation] in
            while !Task.isCancelled {
                do {
                    guard let message = HWebSocketMessage(try await task.receive()) else {
                        throw URLError(.cannotParseResponse)
                    }
                    await self.logContext?.logReceived(message)
                    continuation.yield(message)
                } catch {
                    await self.handleReceiveFailure(error)
                    return
                }
            }
        }

        if let pingInterval {
            pingTask = Task { [task] in
                while !Task.isCancelled {
                    guard await Self.sleep(seconds: pingInterval) else { return }
                    switch await Self.ping(task, timeout: pingInterval) {
                    case .pong:
                        continue
                    case .failed:
                        // The connection is closing or lost: the receive loop classifies it
                        // (close frame vs. transport failure) so the real reason is reported.
                        return
                    case .timedOut:
                        await self.pingTimedOut()
                        return
                    }
                }
            }
        }
    }

    /// Handles the end of the receive loop. A close frame (the task's close code, or the one
    /// the delegate recorded) ends the stream normally; anything else is a lost connection and
    /// the stream throws the mapped error. `receive()` can fail before `URLSession` delivers
    /// the close frame to the delegate, so the decision waits for the task to complete
    /// (`didCompleteWithError`, which follows `didCloseWith`), bounded by
    /// `completionGracePeriod` in case the completion never arrives.
    /// - Parameter error: The error `receive()` failed with.
    private func handleReceiveFailure(_ error: Error) async {
        guard case .open = state else { return }

        await Self.withTimeout(Self.completionGracePeriod) { [delegate] in
            await delegate.waitForCompletion()
        }
        guard case .open = state else { return }

        if task.closeCode != .invalid {
            await finish(code: task.closeCode, reason: task.closeReason, error: nil, initiatedLocally: false)
        } else if let closeFrame = delegate.closeFrame {
            await finish(code: closeFrame.code, reason: closeFrame.reason, error: nil, initiatedLocally: false)
        } else {
            await finish(code: .abnormalClosure, reason: nil, error: mapped(error), initiatedLocally: false)
        }
    }

    /// Closes a connection whose ping was not answered in time.
    private func pingTimedOut() async {
        guard case .open = state else { return }
        task.cancel()
        await finish(code: .abnormalClosure, reason: nil, error: .pingTimeout, initiatedLocally: true)
    }

    /// Transitions to `.closed`, stops the loops, finishes the stream and releases the session.
    /// - Parameters:
    ///   - code: The close code.
    ///   - reason: The close reason, if any.
    ///   - error: The error the stream throws, or `nil` to finish it normally.
    ///   - initiatedLocally: Whether the app closed the connection.
    private func finish(code: URLSessionWebSocketTask.CloseCode, reason: Data?, error: HWebSocketError?, initiatedLocally: Bool) async {
        state = .closed(code: code, reason: reason)
        receiveTask?.cancel()
        pingTask?.cancel()
        receiveTask = nil
        pingTask = nil
        if let error {
            await logContext?.logError(error)
            continuation.finish(throwing: error)
        } else {
            await logContext?.logClose(code: code, reason: reason, initiatedLocally: initiatedLocally)
            continuation.finish()
        }
        let session = session
        await HRequestManager.releaseURLSession(session)
    }

    /// Sends a message through the task.
    /// - Parameter message: The message.
    /// - Throws: `.notConnected` when the connection is closed, or the transport error.
    private func send(message: HWebSocketMessage) async throws(HWebSocketError) {
        guard case .open = state else { throw .notConnected }
        do {
            try await task.send(message.taskMessage)
        } catch {
            throw mapped(error)
        }
        await logContext?.logSent(message)
    }

    /// Maps an error thrown by the task to an `HWebSocketError`. A message above
    /// `maximumMessageSize` surfaces from `URLSession` as the POSIX error `EMSGSIZE`.
    /// - Parameter error: The thrown error.
    private func mapped(_ error: Error) -> HWebSocketError {
        if let urlError = error as? URLError {
            return HWebSocketError(hRequestError: HRequestManager.mapTransportError(urlError, trustEvaluationFailed: delegate.trustEvaluationFailed))
        }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EMSGSIZE) {
            return .messageTooBig
        }
        return HWebSocketError(hRequestError: HRequestManager.mapNonURLError(error))
    }
}

// MARK: - Pings

extension HWebSocket {
    /// How a ping ended.
    private enum PingOutcome: Sendable {
        /// The pong arrived.
        case pong
        /// `URLSession` reported an error (the connection is closing or lost).
        case failed(Error)
        /// Neither a pong nor an error arrived within the timeout.
        case timedOut
    }

    /// How long `ping()` waits for the pong when the request sets no `pingInterval`.
    static let defaultPingTimeout: TimeInterval = 10

    /// How long a failed `receive()` waits for the task completion before treating the
    /// connection as lost.
    private static let completionGracePeriod: TimeInterval = 3

    /// Sends a ping and waits for the pong. `sendPing(pongReceiveHandler:)` has no `async`
    /// form and its handler has been seen to fire twice (or never, on a dead connection), so
    /// the continuation is resumed once, and cancelling the waiting task resumes it with
    /// `CancellationError` (also when the task was already cancelled on entry).
    /// - Parameter task: The task to ping.
    /// - Throws: The error reported with the pong, if any.
    private static func sendPing(on task: URLSessionWebSocketTask) async throws {
        let pending = HLockedState<CheckedContinuation<Void, Error>?>(nil)
        let takePending: @Sendable () -> CheckedContinuation<Void, Error>? = {
            pending.withLock { pending in
                defer { pending = nil }
                return pending
            }
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pending.withLock { $0 = continuation }
                // `onCancel` already ran (to no effect) when the task was cancelled on entry.
                if Task.isCancelled {
                    takePending()?.resume(throwing: CancellationError())
                    return
                }
                task.sendPing { error in
                    guard let continuation = takePending() else { return }
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } onCancel: {
            takePending()?.resume(throwing: CancellationError())
        }
    }

    /// Pings the task and waits at most `timeout` seconds for the pong.
    /// - Parameters:
    ///   - task: The task to ping.
    ///   - timeout: The time to wait for the pong, in seconds.
    private static func ping(_ task: URLSessionWebSocketTask, timeout: TimeInterval) async -> PingOutcome {
        let outcome: PingOutcome? = await withTimeout(timeout) {
            do {
                try await sendPing(on: task)
                return .pong
            } catch {
                return .failed(error)
            }
        }
        return outcome ?? .timedOut
    }

    /// Runs `operation` and gives up after `timeout` seconds. Both children honor
    /// cancellation, so the group never waits past the timeout.
    /// - Parameters:
    ///   - timeout: The time to wait, in seconds.
    ///   - operation: The operation.
    /// - Returns: The operation's result, or `nil` when it did not finish in time.
    @discardableResult
    private static func withTimeout<Result: Sendable>(_ timeout: TimeInterval, _ operation: @escaping @Sendable () async -> Result) async -> Result? {
        await withTaskGroup(of: Result?.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                _ = await sleep(seconds: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Longest sleep accepted by the ping and timeout helpers: one day.
    private static let maxSleep: TimeInterval = 86_400

    /// Sleeps through the shared helper, capped at `maxSleep`.
    /// - Parameter seconds: The duration.
    /// - Returns: `false` when the task was cancelled before or during the sleep.
    private static func sleep(seconds: TimeInterval) async -> Bool {
        await HRequestManager.sleep(seconds: seconds, maximum: maxSleep)
    }
}
