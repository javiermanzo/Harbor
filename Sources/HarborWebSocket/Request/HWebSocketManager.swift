//
//  HWebSocketManager.swift
//  HarborWebSocket
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation
import Harbor

/// Runs the WebSocket handshake pipeline: URL building, connectivity pre-check, authentication
/// (with the `401` refresh flow), retries and session leasing. Isolated to Harbor's global
/// actor so it reads the shared configuration safely. The attempt loop itself (retries,
/// `Retry-After`, the auth refresh and the cancellation check) is Harbor's
/// `HRequestManager.runAttemptLoop`, shared with REST requests.
@HRequestManagerActor
enum HWebSocketManager {
    /// Schemes accepted in a request URL. `http`/`https` are rewritten to `ws`/`wss`.
    static let allowedSchemes: Set<String> = ["ws", "wss", "http", "https"]

    /// Outcome of the handshake loop: the open connection, or the error to throw.
    private typealias ConnectResult = Result<HWebSocket, HWebSocketError>
}

// MARK: - Connect

extension HWebSocketManager {
    /// Opens a connection for the request.
    /// - Parameter request: The endpoint description.
    /// - Returns: The open connection.
    /// - Throws: An `HWebSocketError` when the handshake fails.
    static func connect<Request: HWebSocketRequestProtocol>(request: Request) async throws(HWebSocketError) -> HWebSocket {
        let logContext = HWebSocketLogContext(request: request)
        let url: URL
        do {
            url = try webSocketURL(for: request)
        } catch {
            await logContext?.logError(error)
            throw error
        }

        guard HRequestManager.connectivityMonitor.isConnectedToNetwork() else {
            await logContext?.logError(.noConnection)
            throw .noConnection
        }

        let authHeader: HAuthorizationHeader?
        switch await HRequestManager.authorizationHeader(needsAuth: request.needsAuth) {
        case .failure(let hError):
            let error = HWebSocketError(hRequestError: hError)
            await logContext?.logError(error)
            throw error
        case .success(let header):
            authHeader = header
        }

        let result: ConnectResult = await HRequestManager.runAttemptLoop(
            needsAuth: request.needsAuth,
            retryPolicy: request.retryPolicy,
            authHeader: authHeader,
            failWith: { hError in
                let error = HWebSocketError(hRequestError: hError)
                await logContext?.logError(error)
                return .failure(error)
            }
        ) { currentAuthHeader, canRetry in
            await attempt(request: request, url: url, authHeader: currentAuthHeader, canRetry: canRetry, logContext: logContext)
        }

        switch result {
        case .success(let socket):
            return socket
        case .failure(let error):
            throw error
        }
    }

    /// Performs one handshake: builds the request, starts the task on a leased session and
    /// waits for it to open. On failure the lease is released and the outcome tells the loop
    /// whether to retry, refresh the credentials or give up.
    /// - Parameters:
    ///   - request: The endpoint description.
    ///   - url: The resolved endpoint URL.
    ///   - authHeader: The authorization header to send, if any.
    ///   - canRetry: Whether the loop can run another attempt.
    ///   - logContext: The logging context when the request opted into logging.
    private static func attempt<Request: HWebSocketRequestProtocol>(request: Request, url: URL, authHeader: HAuthorizationHeader?, canRetry: Bool, logContext: HWebSocketLogContext?) async -> HAttemptOutcome<ConnectResult> {
        let urlRequest = handshakeRequest(for: request, url: url, authHeader: authHeader)
        await logContext?.logHandshake(urlRequest: urlRequest, subprotocols: request.subprotocols)

        // Leased until the connection closes (see `HWebSocket`), so a configuration change
        // meanwhile only retires the session instead of invalidating it under the task.
        let session = HRequestManager.leaseURLSession(profile: .webSocket)
        let delegate = HWebSocketTaskDelegate(authHeaderKey: authHeader?.key)
        let task = session.webSocketTask(with: urlRequest)
        task.delegate = delegate
        if let maximumMessageSize = request.maximumMessageSize, maximumMessageSize > 0 {
            task.maximumMessageSize = maximumMessageSize
        }

        let startTime = Date()
        task.resume()

        do {
            // Cancelling the calling task cancels the handshake, which completes the task with
            // `URLError.cancelled` and resumes the waiter.
            let subprotocol = try await withTaskCancellationHandler {
                try await delegate.waitForOpen()
            } onCancel: {
                task.cancel()
            }

            // A cancellation that lands right after the handshake succeeded has already
            // cancelled the task: never hand out a connection that is dying.
            guard !Task.isCancelled else {
                task.cancel(with: .goingAway, reason: nil)
                HRequestManager.releaseURLSession(session)
                return .finish(.failure(.cancelled))
            }

            let socket = HWebSocket(task: task,
                                    session: session,
                                    delegate: delegate,
                                    negotiatedSubprotocol: subprotocol,
                                    pingInterval: request.pingInterval ?? HWebSocketConfig.shared.pingInterval,
                                    logContext: logContext)
            await socket.start()
            await logContext?.logOpen(subprotocol: subprotocol, duration: Date().timeIntervalSince(startTime) * 1000)
            return .finish(.success(socket))
        } catch {
            HRequestManager.releaseURLSession(session)
            let outcome = failureOutcome(error, task: task, delegate: delegate, request: request, canRetry: canRetry)
            if case .finish(.failure(let failure)) = outcome {
                await logContext?.logError(failure)
            }
            return outcome
        }
    }

    /// Classifies a failed handshake. A non-101 status is read from the task's response: `401`
    /// goes through the auth refresh flow, retryable statuses honor the retry policy (and
    /// `Retry-After`), the rest fail with `.handshakeFailed`. Transport errors are mapped like
    /// REST attempts: a rejected TLS challenge is `.certificate`, never retried.
    /// - Parameters:
    ///   - error: The error the task completed with.
    ///   - task: The failed task.
    ///   - delegate: The task delegate, which knows whether TLS was rejected.
    ///   - request: The endpoint description.
    ///   - canRetry: Whether the loop can run another attempt.
    private static func failureOutcome<Request: HWebSocketRequestProtocol>(_ error: Error, task: URLSessionWebSocketTask, delegate: HWebSocketTaskDelegate, request: Request, canRetry: Bool) -> HAttemptOutcome<ConnectResult> {
        if let httpResponse = task.response as? HTTPURLResponse, httpResponse.statusCode != 101, !delegate.trustEvaluationFailed {
            let statusCode = httpResponse.statusCode
            if statusCode == 401 {
                return .unauthorized
            }
            if canRetry, request.retryPolicy?.shouldRetry(statusCode: statusCode, method: .get) == true,
               case .retry(let retryAfter) = HRequestManager.statusRetry(statusCode: statusCode, httpResponse: httpResponse) {
                return .retry(after: retryAfter)
            }
            return .finish(.failure(.handshakeFailed(statusCode: statusCode)))
        }

        if let urlError = error as? URLError {
            let hError = HRequestManager.mapTransportError(urlError, trustEvaluationFailed: delegate.trustEvaluationFailed)
            if hError != .certificate, hError != .cancelled, canRetry,
               request.retryPolicy?.shouldRetry(urlError: urlError, method: .get) == true {
                return .retry(after: nil)
            }
            return .finish(.failure(HWebSocketError(hRequestError: hError)))
        }

        return .finish(.failure(HWebSocketError(hRequestError: HRequestManager.mapNonURLError(error))))
    }
}

// MARK: - Request Building

extension HWebSocketManager {
    /// Builds the endpoint URL: path and query parameters are encoded like REST requests, and
    /// `http`/`https` are rewritten to `ws`/`wss`.
    /// - Parameter request: The endpoint description.
    /// - Throws: `.invalidURL` when the URL cannot be built or uses another scheme.
    static func webSocketURL<Request: HWebSocketRequestProtocol>(for request: Request) throws(HWebSocketError) -> URL {
        let url: URL
        do {
            url = try HURLBuilder.compositeURL(url: request.url,
                                               pathParameters: request.pathParameters,
                                               queryParameters: request.queryParameters,
                                               allowedSchemes: allowedSchemes)
        } catch let hError as HRequestError {
            throw HWebSocketError(hRequestError: hError)
        } catch {
            throw .invalidURL(reason: String(describing: error))
        }

        switch url.scheme?.lowercased() {
        case "http":
            return try rewritingScheme(of: url, to: "ws")
        case "https":
            return try rewritingScheme(of: url, to: "wss")
        default:
            return url
        }
    }

    /// Returns the URL with its scheme replaced.
    /// - Parameters:
    ///   - url: The URL.
    ///   - scheme: The new scheme.
    /// - Throws: `.invalidURL` when the URL cannot be rebuilt.
    private static func rewritingScheme(of url: URL, to scheme: String) throws(HWebSocketError) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw .invalidURL(reason: "Invalid URL")
        }
        components.scheme = scheme
        guard let rewritten = components.url else {
            throw .invalidURL(reason: "Invalid URL")
        }
        return rewritten
    }

    /// Builds the handshake request: timeout, cookie flag, `Harbor`'s default headers, the
    /// request headers, the offered subprotocols and the authorization header, in that order
    /// (later values replace earlier ones for the same header name).
    /// - Parameters:
    ///   - request: The endpoint description.
    ///   - url: The resolved endpoint URL.
    ///   - authHeader: The authorization header to send, if any.
    static func handshakeRequest<Request: HWebSocketRequestProtocol>(for request: Request, url: URL, authHeader: HAuthorizationHeader?) -> URLRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = request.timeoutInterval ?? HConfig.shared.timeoutInterval
        urlRequest.httpShouldHandleCookies = HConfig.shared.httpShouldHandleCookies

        for (key, value) in HConfig.shared.defaultHeaderParameters ?? [:] {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        for (key, value) in request.headerParameters ?? [:] {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let subprotocols = request.subprotocols.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !subprotocols.isEmpty {
            urlRequest.setValue(subprotocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }

        if let authHeader {
            urlRequest.setValue(authHeader.value, forHTTPHeaderField: authHeader.key)
            // Redact the provider's header in debug output even under a non-standard name.
            HRedactionPolicy.registerAuthHeaderKey(authHeader.key)
        }

        return urlRequest
    }
}
