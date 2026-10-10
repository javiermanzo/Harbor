//
//  HRequestManager+Execution.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - Request With Result
extension HRequestManager {
    /// Executes a request that expects a typed model response.
    /// - Parameters:
    ///   - model: The expected model type to decode.
    ///   - request: The request conforming to `HRequestWithResultProtocol`.
    /// - Returns: `HResponseWithResult<Model>` containing parsed result or error.
    static func request<Model: HModel, Request: HRequestWithResultProtocol>(model: Model.Type, request: Request) async -> HResponseWithResult<Model> {
        let retryPolicy = request.retryPolicy

        if HConfig.shared.mocksEnabled, HMocker.isRegistered(type(of: request)) {
            return await runAttempts(
                request: request,
                retryPolicy: retryPolicy,
                authHeader: nil,
                errorResponse: { .error($0) }
            ) { currentRequest, _, canRetry in
                return await executeMockAttempt(model: model, request: currentRequest, canRetry: canRetry)
            }
        }

        if !connectivityMonitor.isConnectedToNetwork() {
            if let getRequest = request as? any HGetRequestProtocol {
                // Offline: serve a fresh custom-cache entry, the URLCache response or a
                // stale-if-error entry before failing. Requests that do not need auth never
                // consult the provider. Requests that need auth only look up the entry
                // namespaced by their credential (the entry stored without credentials, e.g.
                // while logged out, is never served in its place): the credential the request
                // last succeeded with is reused when known, so the provider, whose header
                // resolution may refresh a token over the network, is only consulted for
                // requests that never succeeded online.
                let authHeader: HAuthorizationHeader?
                if let remembered = rememberedAuthHeader(for: getRequest) {
                    authHeader = remembered
                } else {
                    authHeader = await cacheAuthHeader(for: request)
                }
                if let cached = await getRequest.offlineCache(authHeader: authHeader, resolvingAuthHeader: false) as? Model {
                    HCacheFallbackProbe.markServedFromCache()
                    return .success(cached)
                }
            }
            let hError: HRequestError = .noConnection
            await logError(hError, request: request)
            return .error(hError)
        }

        switch await authorizationHeaderIfNeeded(for: request) {
        case .failure(let hError):
            await logError(hError, request: request)
            return .error(hError)
        case .success(let authHeader):
            return await runAttempts(
                request: request,
                retryPolicy: retryPolicy,
                authHeader: authHeader,
                errorResponse: { .error($0) }
            ) { currentRequest, currentAuthHeader, canRetry in
                return await executeOnce(model: model, request: currentRequest, authHeader: currentAuthHeader, canRetry: canRetry)
            }
        }
    }

    /// Executes a single mocked attempt. The mock is resolved on every attempt, so a
    /// registered `HMockSequence` advances across retries and 401 re-attempts.
    /// - Parameters:
    ///   - model: The expected model type to decode.
    ///   - request: The request conforming to `HRequestWithResultProtocol`.
    ///   - canRetry: Whether further retry attempts are available.
    /// - Returns: `HAttemptOutcome` carrying the response or next loop action.
    private static func executeMockAttempt<Model: HModel, Request: HRequestWithResultProtocol>(model: Model.Type, request: Request, canRetry: Bool) async -> HAttemptOutcome<HResponseWithResult<Model>> {
        let generation = cacheGeneration
        let mock: HMock
        switch await resolveMock(for: request) {
        case .failure(let hError):
            return await mockFailureOutcome(hError, request: request, canRetry: canRetry) { .error($0) }
        case .success(let resolvedMock):
            mock = resolvedMock
        }

        if mock.jsonResponse == nil, (200 ... 299).contains(mock.statusCode) {
            HLogger.log("Mock for \(request) returned status \(mock.statusCode) with no body; decoding will fail for model-returning requests", level: .warning)
        }

        let mockResponse = HTTPURLResponse(url: mockURL(for: request), statusCode: mock.statusCode, httpVersion: nil, headerFields: mock.headers)
        return await processResponse(model: model,
                                     request: request,
                                     statusCode: mock.statusCode,
                                     data: mock.responseBody,
                                     httpResponse: mockResponse,
                                     canRetry: canRetry,
                                     generation: generation)
    }

    /// Executes a single network attempt: builds the URLRequest, performs the call and
    /// processes the response. `canRetry` tells whether the loop can run another attempt,
    /// so retryable failures are reported as `.retry` only while attempts remain.
    ///
    /// When a conditional request whose validators Harbor injected from its custom cache is
    /// answered with `304 Not Modified` but no cached body can be served, the request is
    /// re-issued once without the validators and that response is used instead. Validators
    /// set by the caller are never stripped: the `304` is returned to the caller.
    /// - Parameters:
    ///   - model: The expected model type to decode.
    ///   - request: The request conforming to `HRequestWithResultProtocol`.
    ///   - authHeader: Optional authorization header to apply.
    ///   - canRetry: Whether further retry attempts are available.
    /// - Returns: `HAttemptOutcome` carrying the response or next loop action.
    private static func executeOnce<Model: HModel, Request: HRequestWithResultProtocol>(model: Model.Type, request: Request, authHeader: HAuthorizationHeader?, canRetry: Bool) async -> HAttemptOutcome<HResponseWithResult<Model>> {
        let generation = cacheGeneration
        let prepared: HURLBuilder.HPreparedRequest
        do {
            prepared = try await HURLBuilder.prepareRequest(request: request, authHeader: authHeader)
        } catch let hError as HRequestError {
            await logError(hError, request: request)
            return .finish(.error(hError))
        } catch {
            let hError: HRequestError = .malformedRequest(reason: String(describing: error))
            await logError(hError, request: request)
            return .finish(.error(hError))
        }
        // A streamed multipart body lives in a temporary file for the duration of the attempt.
        defer { prepared.removeBodyFile() }
        var urlRequest = prepared.urlRequest

        // Leased for the whole attempt (including a 304 refetch): a session-affecting
        // configuration change or a session-cache eviction meanwhile only retires it, so no
        // task is ever created on an invalidated session.
        let session = leaseURLSession(for: request)
        defer { releaseURLSession(session) }

        while true {
            if let request = request as? HDebugRequestProtocol {
                await request.logRequest(urlRequest: urlRequest)
            }

            let startTime = Date()
            let taskContext = HTaskContext(authHeaderKey: authHeader?.key)

            do {
                let (data, httpResponse) = try await perform(urlRequest, bodyFileURL: prepared.bodyFileURL, session: session, delegate: taskContext)

                let duration = Date().timeIntervalSince(startTime) * 1000

                guard let httpResponse = httpResponse as? HTTPURLResponse else {
                    if canRetry, request.retryPolicy?.allowsRetry(for: request.httpMethod) == true {
                        return .retry(after: nil)
                    }
                    let hError: HRequestError = .invalidHttpResponse
                    await logError(hError, request: request)
                    return .finish(.error(hError))
                }

                if let request = request as? HDebugRequestProtocol {
                    await request.logResponse(httpResponse: httpResponse, data: data, duration: duration)
                }

                let outcome = await processResponse(model: model,
                                                    request: request,
                                                    statusCode: httpResponse.statusCode,
                                                    data: data,
                                                    httpResponse: httpResponse,
                                                    canRetry: canRetry,
                                                    authHeader: authHeader,
                                                    canRefetchUnconditionally: prepared.injectedConditionalValidators && hasConditionalValidators(urlRequest),
                                                    generation: generation)
                if case .refetchUnconditionally = outcome {
                    removeConditionalValidators(from: &urlRequest)
                    continue
                }
                return outcome
            } catch let error as URLError {
                let hError = mapTransportError(error, trustEvaluationFailed: taskContext.trustEvaluationFailed)
                if hError == .certificate || hError == .cancelled {
                    // A rejected TLS handshake is never retried nor masked by cached content.
                    await logError(hError, request: request)
                    return .finish(.error(hError))
                }
                if canRetry, request.retryPolicy?.shouldRetry(urlError: error, method: request.httpMethod) == true {
                    return .retry(after: nil)
                }
                // Cached content is only a fallback once retries are exhausted or the error is
                // not retryable. Without connectivity a fresh entry (or the URLCache response)
                // is served too, under the credential the attempt used or, when it was sent
                // without one, the credential the request last succeeded with; any other
                // error only falls back to stale-if-error content.
                if let getRequest = request as? any HGetRequestProtocol {
                    let fallback: Any?
                    if hError == .noConnection {
                        let offlineHeader = authHeader ?? rememberedAuthHeader(for: getRequest)
                        fallback = await getRequest.offlineCache(authHeader: offlineHeader, resolvingAuthHeader: false)
                    } else {
                        fallback = await getRequest.staleCacheOnError(authHeader: authHeader)
                    }
                    if let cached = fallback as? Model {
                        HCacheFallbackProbe.markServedFromCache()
                        return .finish(.success(cached))
                    }
                }
                await logError(hError, request: request)
                return .finish(.error(hError))
            } catch {
                let hError = mapNonURLError(error)
                await logError(hError, request: request)
                return .finish(.error(hError))
            }
        }
    }

    /// Processes the raw response for a model-returning request, decoding the payload or handling errors/revalidation.
    /// `authHeader` keys the custom-cache reads and writes so `Vary: Authorization` entries are per-credential.
    /// - Parameters:
    ///   - model: The expected model type to decode.
    ///   - request: The request conforming to `HRequestWithResultProtocol`.
    ///   - statusCode: HTTP status code.
    ///   - data: Raw response payload.
    ///   - httpResponse: Optional HTTPURLResponse object.
    ///   - canRetry: Whether further retries remain.
    ///   - authHeader: Optional authorization header used for vary keying.
    ///   - canRefetchUnconditionally: Whether a `304` without a cached body may be answered by
    ///     re-issuing the request without conditional validators (only when Harbor injected them).
    ///   - generation: The `cacheGeneration` when the attempt started. The response is only
    ///     cached when it is still current.
    /// - Returns: `HAttemptOutcome` carrying the response or next loop action.
    private static func processResponse<Model: HModel, Request: HRequestWithResultProtocol>(model: Model.Type, request: Request, statusCode: Int, data: Data, httpResponse: HTTPURLResponse? = nil, canRetry: Bool = false, authHeader: HAuthorizationHeader? = nil, canRefetchUnconditionally: Bool = false, generation: Int) async -> HAttemptOutcome<HResponseWithResult<Model>> {
        switch statusCode {
        case 200 ... 299:
            do {
                let parsedResponse = try await decode(data, as: model, using: request)
                HCacheFallbackProbe.markServedFromNetwork()

                if let request = request as? any HGetRequestProtocol, generation == cacheGeneration,
                   request.shouldCache(statusCode: statusCode) {
                    await request.saveCache(data, response: httpResponse, authHeader: authHeader)
                    if generation == cacheGeneration {
                        rememberAuthHeader(authHeader, for: request)
                    }
                }

                return .finish(.success(parsedResponse))
            } catch let parseError {
                let hError: HRequestError = .codable(modelName: "\(model.self)", error: parseError)
                await logError(hError, request: request)
                return .finish(.error(hError))
            }
        case 304:
            // Not Modified — serve the cached body and refresh the stored entry.
            // (URLCache revalidates transparently at URLSession level; this branch handles the custom cache.)
            if let getRequest = request as? any HGetRequestProtocol,
               let cachedAny = await getRequest.revalidatedCache(response: httpResponse, authHeader: authHeader),
               let cachedModel = cachedAny as? Model {
                if generation == cacheGeneration {
                    rememberAuthHeader(authHeader, for: getRequest)
                }
                return .finish(.success(cachedModel))
            }
            // The validators matched but the body is gone (evicted, or another vary variant):
            // ask the caller to fetch the full representation instead of failing.
            if canRefetchUnconditionally {
                return .refetchUnconditionally
            }
            let hError: HRequestError = .api(statusCode: statusCode, data: data)
            await logError(hError, request: request)
            return .finish(.error(hError))
        case 401:
            return .unauthorized
        default:
            // Retries take precedence; stale content is only a fallback once they are exhausted.
            if canRetry, request.retryPolicy?.shouldRetry(statusCode: statusCode, method: request.httpMethod) == true,
               case .retry(let retryAfter) = statusRetry(statusCode: statusCode, httpResponse: httpResponse) {
                return .retry(after: retryAfter)
            }
            if statusCode >= 500,
               let getRequest = request as? any HGetRequestProtocol,
               let stale = await getRequest.staleCacheOnError(authHeader: authHeader) as? Model {
                HCacheFallbackProbe.markServedFromCache()
                return .finish(.success(stale))
            }
            let hError: HRequestError = .api(statusCode: statusCode, data: data)
            await logError(hError, request: request)
            return .finish(.error(hError))
        }
    }

    /// Decodes the payload off `HRequestManagerActor`, so concurrent requests do not
    /// serialize their decoding on the actor. Being `nonisolated` and `async`, it runs on
    /// the global concurrent executor; the request, data and decoded model are `Sendable`.
    /// - Parameters:
    ///   - data: Raw response payload.
    ///   - model: The expected model type to decode.
    ///   - request: The request whose `parseData(data:model:)` performs the decoding.
    /// - Returns: The decoded model.
    /// - Throws: The error thrown by `parseData(data:model:)`.
    nonisolated private static func decode<Model: HModel, Request: HRequestWithResultProtocol>(_ data: Data, as model: Model.Type, using request: Request) async throws -> Model {
        try request.parseData(data: data, model: model)
    }
}

// MARK: - Request Without Result
extension HRequestManager {
    /// Executes a request that expects an empty response.
    /// - Parameter request: The request conforming to `HRequestWithEmptyResponseProtocol`.
    /// - Returns: `HResponse` indicating success or failure.
    static func request<Request: HRequestWithEmptyResponseProtocol>(request: Request) async -> HResponse {
        let retryPolicy = request.retryPolicy

        if HConfig.shared.mocksEnabled, HMocker.isRegistered(type(of: request)) {
            return await runAttempts(
                request: request,
                retryPolicy: retryPolicy,
                authHeader: nil,
                errorResponse: { .error($0) }
            ) { currentRequest, _, canRetry in
                return await executeMockAttempt(request: currentRequest, canRetry: canRetry)
            }
        }

        if !connectivityMonitor.isConnectedToNetwork() {
            let hError: HRequestError = .noConnection
            await logError(hError, request: request)
            return .error(hError)
        }

        switch await authorizationHeaderIfNeeded(for: request) {
        case .failure(let hError):
            await logError(hError, request: request)
            return .error(hError)
        case .success(let authHeader):
            return await runAttempts(
                request: request,
                retryPolicy: retryPolicy,
                authHeader: authHeader,
                errorResponse: { .error($0) }
            ) { currentRequest, currentAuthHeader, canRetry in
                return await executeOnce(request: currentRequest, authHeader: currentAuthHeader, canRetry: canRetry)
            }
        }
    }

    /// Executes a single mocked attempt. The mock is resolved on every attempt, so a
    /// registered `HMockSequence` advances across retries and 401 re-attempts.
    /// - Parameters:
    ///   - request: The request conforming to `HRequestWithEmptyResponseProtocol`.
    ///   - canRetry: Whether further retry attempts are available.
    /// - Returns: `HAttemptOutcome` carrying the response or next loop action.
    private static func executeMockAttempt<Request: HRequestWithEmptyResponseProtocol>(request: Request, canRetry: Bool) async -> HAttemptOutcome<HResponse> {
        switch await resolveMock(for: request) {
        case .failure(let hError):
            return await mockFailureOutcome(hError, request: request, canRetry: canRetry) { .error($0) }
        case .success(let mock):
            let mockResponse = HTTPURLResponse(url: mockURL(for: request), statusCode: mock.statusCode, httpVersion: nil, headerFields: mock.headers)
            return await processResponse(request: request, statusCode: mock.statusCode, data: mock.responseBody, canRetry: canRetry, httpResponse: mockResponse)
        }
    }

    /// Executes a single network attempt: builds the URLRequest, performs the call and
    /// processes the response. `canRetry` tells whether the loop can run another attempt,
    /// so retryable failures are reported as `.retry` only while attempts remain.
    /// - Parameters:
    ///   - request: The request conforming to `HRequestWithEmptyResponseProtocol`.
    ///   - authHeader: Optional authorization header to apply.
    ///   - canRetry: Whether further retry attempts are available.
    /// - Returns: `HAttemptOutcome` carrying the response or next loop action.
    private static func executeOnce<Request: HRequestWithEmptyResponseProtocol>(request: Request, authHeader: HAuthorizationHeader?, canRetry: Bool) async -> HAttemptOutcome<HResponse> {
        let prepared: HURLBuilder.HPreparedRequest
        do {
            prepared = try await HURLBuilder.prepareRequest(request: request, authHeader: authHeader)
        } catch let hError as HRequestError {
            await logError(hError, request: request)
            return .finish(.error(hError))
        } catch {
            let hError: HRequestError = .malformedRequest(reason: String(describing: error))
            await logError(hError, request: request)
            return .finish(.error(hError))
        }
        // A streamed multipart body lives in a temporary file for the duration of the attempt.
        defer { prepared.removeBodyFile() }
        let urlRequest = prepared.urlRequest

        // Leased for the whole attempt so it cannot be invalidated before its task is created.
        let session = leaseURLSession(for: request)
        defer { releaseURLSession(session) }

        if let request = request as? HDebugRequestProtocol {
            await request.logRequest(urlRequest: urlRequest)
        }

        let startTime = Date()
        let taskContext = HTaskContext(authHeaderKey: authHeader?.key)

        do {
            let (data, httpResponse) = try await perform(urlRequest, bodyFileURL: prepared.bodyFileURL, session: session, delegate: taskContext)

            let duration = Date().timeIntervalSince(startTime) * 1000

            guard let httpResponse = httpResponse as? HTTPURLResponse else {
                if canRetry, request.retryPolicy?.allowsRetry(for: request.httpMethod) == true {
                    return .retry(after: nil)
                }
                let hError: HRequestError = .invalidHttpResponse
                await logError(hError, request: request)
                return .finish(.error(hError))
            }

            if let request = request as? HDebugRequestProtocol {
                await request.logResponse(httpResponse: httpResponse, data: data, duration: duration)
            }

            return await processResponse(request: request, statusCode: httpResponse.statusCode, data: data, canRetry: canRetry, httpResponse: httpResponse)
        } catch let error as URLError {
            let hError = mapTransportError(error, trustEvaluationFailed: taskContext.trustEvaluationFailed)
            if hError != .certificate, hError != .cancelled, canRetry, request.retryPolicy?.shouldRetry(urlError: error, method: request.httpMethod) == true {
                return .retry(after: nil)
            }
            await logError(hError, request: request)
            return .finish(.error(hError))
        } catch {
            let hError = mapNonURLError(error)
            await logError(hError, request: request)
            return .finish(.error(hError))
        }
    }

    /// Processes the raw response for an empty-response request, checking status codes and handling errors.
    /// - Parameters:
    ///   - request: The request conforming to `HRequestWithEmptyResponseProtocol`.
    ///   - statusCode: HTTP status code.
    ///   - data: Raw response payload.
    ///   - canRetry: Whether further retries remain.
    ///   - httpResponse: Optional HTTPURLResponse object.
    /// - Returns: `HAttemptOutcome` carrying the response or next loop action.
    private static func processResponse<Request: HRequestWithEmptyResponseProtocol>(request: Request, statusCode: Int, data: Data, canRetry: Bool = false, httpResponse: HTTPURLResponse? = nil) async -> HAttemptOutcome<HResponse> {
        switch statusCode {
        case 200 ... 299:
            return .finish(.success)
        case 304:
            // Not Modified — the cached representation is still valid; there is no body to serve.
            return .finish(.success)
        case 401:
            return .unauthorized
        default:
            if canRetry, request.retryPolicy?.shouldRetry(statusCode: statusCode, method: request.httpMethod) == true,
               case .retry(let retryAfter) = statusRetry(statusCode: statusCode, httpResponse: httpResponse) {
                return .retry(after: retryAfter)
            }
            let hError: HRequestError = .api(statusCode: statusCode, data: data)
            await logError(hError, request: request)
            return .finish(.error(hError))
        }
    }
}

// MARK: - Request Builder Functions
extension HRequestManager {
    /// Runs the retry loop, delegating each attempt to `executeAttempt`. Connectivity checks
    /// and the initial auth header fetch are evaluated once by the caller, not per attempt.
    /// Each `.retry` outcome waits for its `Retry-After` delay or, when absent, the policy's
    /// backoff before the next attempt; a cancellation during that wait ends the loop with
    /// `.cancelled`. A `401` is handed to `refreshAuthorization`, which notifies the provider
    /// through `authFailed()` at most once over the whole loop.
    /// - Parameters:
    ///   - request: The request object being executed.
    ///   - retryPolicy: Optional retry policy configuration.
    ///   - authHeader: Optional authorization header.
    ///   - errorResponse: Closure mapping errors to the response type.
    ///   - executeAttempt: Closure performing a single attempt.
    /// - Returns: The final `Response` after all attempt iterations.
    private static func runAttempts<TypedRequest: HRequestBaseRequestProtocol & Sendable, Response: Sendable>(
        request: TypedRequest,
        retryPolicy: HRetryPolicy?,
        authHeader: HAuthorizationHeader?,
        errorResponse: @escaping (HRequestError) -> Response,
        executeAttempt: @escaping (TypedRequest, HAuthorizationHeader?, Bool) async -> HAttemptOutcome<Response>
    ) async -> Response {
        var currentAuthHeader = authHeader
        var retriesPerformed = 0
        var authRetriesRemaining = maxAuthRetries
        var providerNotified = false
        var pendingDelay: TimeInterval?
        let maxRetries = retryPolicy?.maxRetries ?? 0

        while true {
            if let delay = pendingDelay {
                pendingDelay = nil
                _ = await sleep(seconds: delay)
            }

            guard !Task.isCancelled else {
                let hError: HRequestError = .cancelled
                await logError(hError, request: request)
                return errorResponse(hError)
            }

            let canRetry = retriesPerformed < maxRetries

            switch await executeAttempt(request, currentAuthHeader, canRetry) {
            case .finish(let response):
                return response
            case .retry(let retryAfter):
                retriesPerformed += 1
                pendingDelay = retryAfter ?? retryPolicy?.delay(forRetry: retriesPerformed) ?? 0
            case .unauthorized:
                switch await refreshAuthorization(needsAuth: request.needsAuth, usedHeader: currentAuthHeader, authRetriesRemaining: authRetriesRemaining, providerNotified: providerNotified) {
                case .retry(let freshHeader, let notified):
                    currentAuthHeader = freshHeader
                    authRetriesRemaining -= 1
                    providerNotified = providerNotified || notified
                case .giveUp(let hError):
                    await logError(hError, request: request)
                    return errorResponse(hError)
                }
            case .refetchUnconditionally:
                // Handled inside the attempt itself; never surfaces to the loop.
                let hError: HRequestError = .api(statusCode: 304, data: Data())
                await logError(hError, request: request)
                return errorResponse(hError)
            }
        }
    }

    /// Performs one network call: an upload task streaming the body from `bodyFileURL` when
    /// it is set (multipart bodies with file parts), a data task otherwise.
    /// - Parameters:
    ///   - urlRequest: The request to send.
    ///   - bodyFileURL: Temporary file holding the request body, if any.
    ///   - session: The session to use.
    ///   - delegate: The per-task delegate.
    /// - Returns: The response body and response.
    private static func perform(_ urlRequest: URLRequest, bodyFileURL: URL?, session: URLSession, delegate: HTaskContext) async throws -> (Data, URLResponse) {
        if let bodyFileURL {
            return try await session.upload(for: urlRequest, fromFile: bodyFileURL, delegate: delegate)
        }
        return try await session.data(for: urlRequest, delegate: delegate)
    }

    /// Whether the request carries conditional validators that can produce a `304`.
    /// - Parameter urlRequest: The built request.
    private static func hasConditionalValidators(_ urlRequest: URLRequest) -> Bool {
        urlRequest.value(forHTTPHeaderField: "If-None-Match") != nil
            || urlRequest.value(forHTTPHeaderField: "If-Modified-Since") != nil
    }

    /// Removes the conditional validators so the server answers with the full representation.
    /// - Parameter urlRequest: The request to modify.
    private static func removeConditionalValidators(from urlRequest: inout URLRequest) {
        urlRequest.setValue(nil, forHTTPHeaderField: "If-None-Match")
        urlRequest.setValue(nil, forHTTPHeaderField: "If-Modified-Since")
    }

    /// Logs an error that occurred during request execution if debug logging is enabled.
    /// - Parameters:
    ///   - error: The error the request failed with.
    ///   - request: The request that failed; only logged when it conforms to `HDebugRequestProtocol`.
    static func logError(_ error: HRequestError, request: HRequestBaseRequestProtocol) async {
        if let request = request as? HDebugRequestProtocol {
            await request.logErrorResponse(error: error)
        }
    }
}
