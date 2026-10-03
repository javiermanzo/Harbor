//
//  HRequestManager.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

/// Global actor to manage shared mutable state in a thread-safe way.
/// This actor ensures that Harbor's internal state is accessed safely across concurrent contexts.
@globalActor public actor HRequestManagerActor {
    /// The shared instance of the actor.
    public static let shared = HRequestManagerActor()
}

@HRequestManagerActor
enum HRequestManager {
    /// Connectivity monitor used as a pre-check before executing requests.
    /// Owned here (typed as the protocol) so tests can substitute a fake.
    static var connectivityMonitor: any HRequestManagerMonitorProtocol = HRequestManagerMonitor()

    /// Maximum number of times a request is re-issued with a refreshed authorization header
    /// after a 401. These attempts are ADDITIONAL to the retry policy's `maxRetries` — they
    /// are not deducted from it. Worst-case total attempts per request are
    /// `1 + retryPolicy.maxRetries + maxAuthRetries`.
    static let maxAuthRetries = 1

    /// In-flight `authFailed()` notifications, keyed by the rejected authorization header.
    /// Concurrent requests rejected with the same credential await the same notification
    /// instead of triggering one refresh each.
    private static var inFlightAuthFailures: [HAuthorizationHeader?: Task<Void, Never>] = [:]

    /// The authorization header each authenticated GET request last succeeded with, keyed by
    /// its plain cache key (the composite URL). Offline lookups use it to find the
    /// credential-namespaced cache entry without consulting the auth provider, whose header
    /// resolution may refresh a token over the network. Cleared by `forgetRememberedAuthHeaders()`
    /// (`Harbor.setAuthProvider(_:)` and `Harbor.clearAllCache()`).
    private static var rememberedAuthHeaders: [String: HAuthorizationHeader] = [:]

    /// Bound of `rememberedAuthHeaders`; past it the map is reset before recording a new entry.
    private static let maxRememberedAuthHeaders = 512
}

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
                                     canRetry: canRetry)
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
                                                    canRefetchUnconditionally: prepared.injectedConditionalValidators && hasConditionalValidators(urlRequest))
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
                        fallback = await getRequest.offlineCache(authHeader: offlineHeader, resolvingAuthHeader: true)
                    } else {
                        fallback = await getRequest.staleCacheOnError(authHeader: authHeader)
                    }
                    if let cached = fallback as? Model {
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
    /// - Returns: `HAttemptOutcome` carrying the response or next loop action.
    private static func processResponse<Model: HModel, Request: HRequestWithResultProtocol>(model: Model.Type, request: Request, statusCode: Int, data: Data, httpResponse: HTTPURLResponse? = nil, canRetry: Bool = false, authHeader: HAuthorizationHeader? = nil, canRefetchUnconditionally: Bool = false) async -> HAttemptOutcome<HResponseWithResult<Model>> {
        switch statusCode {
        case 200 ... 299:
            do {
                let parsedResponse = try await decode(data, as: model, using: request)

                if let request = request as? any HGetRequestProtocol {
                    await request.saveCache(data, response: httpResponse, authHeader: authHeader)
                    rememberAuthHeader(authHeader, for: request)
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
                rememberAuthHeader(authHeader, for: getRequest)
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

    /// Fetches the provider's authorization header for requests that need auth.
    /// Fails with `.authProviderNeeded` when the request needs auth but no provider is
    /// configured. A provider returning `nil` means no credentials are available and the
    /// request goes out without an authorization header.
    /// - Parameter request: The target request.
    /// - Returns: `Result` containing optional header or error.
    static func authorizationHeaderIfNeeded<P: HRequestBaseRequestProtocol>(for request: P) async -> Result<HAuthorizationHeader?, HRequestError> {
        guard request.needsAuth else { return .success(nil) }

        guard let authProvider = HConfig.shared.authProvider else {
            return .failure(.authProviderNeeded)
        }

        return .success(await authProvider.getAuthorizationHeader())
    }

    /// Resolves the authorization header for cache vary-key computation without failing the
    /// flow: a missing provider must not turn a cache lookup into an error.
    /// - Parameter request: The target request.
    /// - Returns: Optional authorization header.
    private static func cacheAuthHeader<P: HRequestBaseRequestProtocol>(for request: P) async -> HAuthorizationHeader? {
        guard case .success(let authHeader) = await authorizationHeaderIfNeeded(for: request) else { return nil }
        return authHeader
    }

    /// Records the credential an authenticated GET request succeeded with, so offline lookups
    /// can find its credential-namespaced cache entry without consulting the provider.
    /// Requests that do not need auth or were sent without credentials record nothing.
    /// - Parameters:
    ///   - authHeader: The authorization header the successful attempt was sent with.
    ///   - request: The request that succeeded.
    private static func rememberAuthHeader(_ authHeader: HAuthorizationHeader?, for request: any HGetRequestProtocol) {
        guard request.needsAuth, let authHeader, let key = request.cacheNamespaceKey() else { return }
        if rememberedAuthHeaders.count >= maxRememberedAuthHeaders, rememberedAuthHeaders[key] == nil {
            rememberedAuthHeaders.removeAll()
        }
        rememberedAuthHeaders[key] = authHeader
    }

    /// The credential an authenticated GET request last succeeded with, if remembered.
    /// - Parameter request: The request being looked up.
    private static func rememberedAuthHeader(for request: any HGetRequestProtocol) -> HAuthorizationHeader? {
        guard request.needsAuth, let key = request.cacheNamespaceKey() else { return nil }
        return rememberedAuthHeaders[key]
    }

    /// Forgets the credentials remembered for offline lookups. Called when the auth provider
    /// is replaced and when the cache is cleared, so a previous user's credential never keys a
    /// lookup for the next one.
    static func forgetRememberedAuthHeaders() {
        rememberedAuthHeaders.removeAll()
    }

    /// Handles a 401 for a request that needs auth. While an auth retry remains, the provider's
    /// current header is compared with the rejected one: a header already rotated (a refresh
    /// triggered by another request completed after this attempt was sent) is retried with
    /// right away, without `authFailed()`; otherwise the provider is notified through
    /// `authFailed()` and asked for its header again, and a retry is offered only when the
    /// header changed. A provider without credentials (a `nil` header) cannot satisfy a 401,
    /// so the flow gives up with `.authNeeded`.
    ///
    /// `authFailed()` is called at most once per request, and always once when a request that
    /// needs auth finally fails with `.authNeeded` after a 401: when the auth retries are
    /// exhausted (the retried attempt was rejected too) and the provider was not notified yet,
    /// it is notified before giving up, so a provider that rotates its header on every call
    /// still learns that its credentials are rejected. Notifications for the same rejected
    /// header are coalesced across concurrent requests (see `notifyAuthFailed`).
    /// `getAuthorizationHeader()` is called at most twice: once to detect a rotated header and,
    /// only after `authFailed()`, once more for the refreshed header.
    /// - Parameters:
    ///   - needsAuth: Whether the request needs auth. A request that opted out has no
    ///     credential to refresh and gives up without consulting the provider.
    ///   - usedHeader: The authorization header the rejected attempt was sent with.
    ///   - authRetriesRemaining: Auth retries still available for this request.
    ///   - providerNotified: Whether `authFailed()` was already called for this request.
    /// - Returns: `.retry` with the header for the next attempt (and whether the provider was
    ///   notified while resolving it), or `.giveUp(.authNeeded)`.
    private static func refreshAuthorization(
        needsAuth: Bool,
        usedHeader: HAuthorizationHeader?,
        authRetriesRemaining: Int,
        providerNotified: Bool
    ) async -> HAuthRefresh {
        guard needsAuth, let authProvider = HConfig.shared.authProvider else {
            return .giveUp(.authNeeded)
        }

        // The retried attempt was rejected too: the request fails with .authNeeded. Make sure
        // the provider learns about it exactly once per request.
        guard authRetriesRemaining > 0 else {
            if !providerNotified {
                await notifyAuthFailed(provider: authProvider, rejectedHeader: usedHeader)
            }
            return .giveUp(.authNeeded)
        }

        // A late 401 for a header the provider has already rotated: retry with the current
        // header instead of asking for another refresh.
        if usedHeader != nil, inFlightAuthFailures[usedHeader] == nil,
           let currentHeader = await authProvider.getAuthorizationHeader(),
           currentHeader != usedHeader {
            return .retry(currentHeader, notifiedProvider: false)
        }

        // Notify the provider of the failure so it can trigger its refresh mechanism, then
        // fetch the header it issues afterwards.
        await notifyAuthFailed(provider: authProvider, rejectedHeader: usedHeader)

        guard let freshHeader = await authProvider.getAuthorizationHeader(),
              freshHeader != usedHeader else {
            return .giveUp(.authNeeded)
        }

        return .retry(freshHeader, notifiedProvider: true)
    }

    /// Calls `authFailed()` on the provider, coalescing concurrent calls: requests rejected
    /// with the same authorization header while a notification for it is in flight await
    /// that notification instead of starting another refresh.
    /// - Parameters:
    ///   - provider: The configured auth provider.
    ///   - rejectedHeader: The authorization header the server rejected.
    private static func notifyAuthFailed(provider: any HAuthProviderProtocol, rejectedHeader: HAuthorizationHeader?) async {
        if let inFlight = inFlightAuthFailures[rejectedHeader] {
            await inFlight.value
            return
        }

        let notification = Task {
            await provider.authFailed()
        }
        inFlightAuthFailures[rejectedHeader] = notification
        await notification.value
        if inFlightAuthFailures[rejectedHeader] == notification {
            inFlightAuthFailures[rejectedHeader] = nil
        }
    }

    /// Resolves the registered mock for one attempt, applying its delay and configured error.
    /// Failures are not logged here: `mockFailureOutcome` logs them once the attempt finishes.
    /// - Parameter request: The request being mocked.
    /// - Returns: The resolved mock, or the error the attempt failed with.
    private static func resolveMock(for request: any HRequestBaseRequestProtocol) async -> Result<HMock, HRequestError> {
        guard let mock = HMocker.mock(request: request) else {
            return .failure(.malformedRequest(reason: "No mock is registered for \(type(of: request))"))
        }

        if let delay = mock.delay, !(await sleep(seconds: delay)) {
            return .failure(.cancelled)
        }

        if let hError = mock.error {
            return .failure(hError)
        }

        return .success(mock)
    }

    /// Outcome of a mocked attempt that failed: a mocked error is classified by the retry
    /// policy exactly like the real failure it stands for (see
    /// `HRetryPolicy.shouldRetry(mockedError:method:)`), so a registered `HMockSequence` can
    /// script a transient failure followed by a success.
    /// - Parameters:
    ///   - hError: The error the attempt failed with.
    ///   - request: The request being mocked.
    ///   - canRetry: Whether further retry attempts are available.
    ///   - errorResponse: Maps the error to the response type.
    /// - Returns: `.retry` for a retryable error while attempts remain, `.finish` otherwise.
    private static func mockFailureOutcome<Response: Sendable>(_ hError: HRequestError, request: any HRequestBaseRequestProtocol, canRetry: Bool, errorResponse: (HRequestError) -> Response) async -> HAttemptOutcome<Response> {
        if hError != .cancelled, !Task.isCancelled, canRetry,
           request.retryPolicy?.shouldRetry(mockedError: hError, method: request.httpMethod) == true {
            return .retry(after: nil)
        }
        await logError(hError, request: request)
        return .finish(errorResponse(hError))
    }

    /// Maps a `URLError` thrown while performing a request. A TLS challenge rejected by
    /// Harbor's session delegate (SSL pinning mismatch, untrusted chain) surfaces from
    /// `URLSession` as `URLError.cancelled`; the task context records it, so it is reported
    /// as `.certificate` instead of `.cancelled`. Otherwise a cancelled task maps to
    /// `.cancelled` and the rest goes through `HRequestError.mapURLError(_:)`.
    /// - Parameters:
    ///   - error: The thrown error.
    ///   - trustEvaluationFailed: Whether Harbor's delegate rejected a TLS challenge for the task.
    /// - Returns: The mapped `HRequestError`.
    static func mapTransportError(_ error: URLError, trustEvaluationFailed: Bool) -> HRequestError {
        if trustEvaluationFailed {
            return .certificate
        }
        if error.code == .cancelled || Task.isCancelled {
            return .cancelled
        }
        return HRequestError.mapURLError(error)
    }

    /// Maps an error that is not a `URLError` thrown while performing a request. Such errors
    /// are never retried; the original error is preserved in `.unknown` unless the task was
    /// cancelled.
    /// - Parameter error: The thrown error.
    /// - Returns: The mapped `HRequestError`.
    private static func mapNonURLError(_ error: Error) -> HRequestError {
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        return .unknown(error)
    }

    /// Delay requested by a `Retry-After` header on a `429` or `503` response, in seconds.
    /// Both forms are supported: delta-seconds and HTTP-date. The value is returned as the
    /// server sent it, not capped (see `statusRetry(statusCode:httpResponse:now:)`); `nil`
    /// means the header is absent, invalid or not applicable.
    /// - Parameters:
    ///   - statusCode: The HTTP status code of the response.
    ///   - httpResponse: The response carrying the header.
    ///   - now: The reference date for HTTP-date values.
    static func retryAfterDelay(statusCode: Int, httpResponse: HTTPURLResponse?, now: Date = Date()) -> TimeInterval? {
        guard statusCode == 429 || statusCode == 503,
              let rawValue = httpResponse?.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        let value = rawValue.trimmingCharacters(in: .whitespaces)
        if let deltaSeconds = Int(value) {
            guard deltaSeconds >= 0 else { return nil }
            return TimeInterval(deltaSeconds)
        }
        if let date = HCache.Manager.parseHTTPDate(value) {
            return max(0, date.timeIntervalSince(now))
        }
        return nil
    }

    /// Decides whether a retryable status code is retried, honoring its `Retry-After` header.
    /// A delay up to `HRetryPolicy.maxDelay` is waited for instead of the policy's backoff. A
    /// longer one is not clamped: the request is not retried and the `.api` error is returned
    /// right away, so the caller sees the server's hint instead of a retry that is too early.
    /// - Parameters:
    ///   - statusCode: The HTTP status code of the response.
    ///   - httpResponse: The response carrying the header.
    ///   - now: The reference date for HTTP-date values.
    static func statusRetry(statusCode: Int, httpResponse: HTTPURLResponse?, now: Date = Date()) -> HStatusRetry {
        let retryAfter = retryAfterDelay(statusCode: statusCode, httpResponse: httpResponse, now: now)
        if let retryAfter, retryAfter > HRetryPolicy.maxDelay {
            return .giveUp
        }
        return .retry(after: retryAfter)
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

    /// Sleeps for the given number of seconds. Negative values are treated as zero and the
    /// delay is clamped to `HRetryPolicy.maxDelay` before converting to nanoseconds.
    /// - Parameter seconds: The duration to sleep, in seconds.
    /// - Returns: `false` when the task was cancelled before or during the sleep.
    @discardableResult
    static func sleep(seconds: TimeInterval) async -> Bool {
        let clampedSeconds = min(max(seconds, 0), HRetryPolicy.maxDelay)
        guard clampedSeconds > 0 else { return !Task.isCancelled }
        do {
            if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
                try await Task.sleep(for: .seconds(clampedSeconds))
            } else {
                try await Task.sleep(nanoseconds: UInt64(clampedSeconds * 1_000_000_000))
            }
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    /// Builds the URL used for synthetic mock responses.
    private static func mockURL(for request: any HRequestBaseRequestProtocol) -> URL {
        if let getRequest = request as? any HGetRequestProtocol,
           let url = try? HURLBuilder.compositeURL(url: getRequest.url, pathParameters: getRequest.pathParameters, queryParameters: getRequest.queryParameters) {
            return url
        }
        return (try? HURLBuilder.compositeURL(url: request.url, pathParameters: request.pathParameters)) ?? URL(fileURLWithPath: "/")
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

// MARK: - URLSession Management
extension HRequestManager {
    /// Inputs that differentiate internally built sessions; requests with different
    /// signatures need different sessions. Timeouts are not part of it: they are set on each
    /// `URLRequest`, so requests with different timeouts share a session.
    private struct SessionSignature: Hashable {
        enum CacheSignature: Hashable {
            case isolated
            case urlCache(ObjectIdentifier, URLRequest.CachePolicy)
        }
        /// The cache configuration for the session.
        var cache: CacheSignature
        /// Whether the session handles cookies through the shared cookie storage.
        var httpShouldHandleCookies: Bool
    }

    /// Maximum number of internally built sessions kept alive at once. Requests alternating
    /// between a few cache configurations each reuse their own session instead of rebuilding
    /// one on every switch; past this bound the least recently used session is retired.
    private static let maxCachedSessions = 4

    /// An internally built session and the last time it was handed out (a monotonic tick).
    private struct CachedSession {
        let session: URLSession
        var lastUse: UInt64
    }

    /// The internally built sessions, keyed by the configuration they were built for.
    private static var cachedSessions: [SessionSignature: CachedSession] = [:]

    /// Monotonic counter ordering session uses, for least-recently-used eviction.
    private static var sessionUseTick: UInt64 = 0

    /// Number of in-flight attempts holding each session (see `leaseURLSession(for:)`).
    private static var sessionLeases: [ObjectIdentifier: Int] = [:]

    /// Sessions dropped from the cache while attempts still held them. They are invalidated
    /// when the last attempt releases them: creating a task on an invalidated session raises
    /// an Objective-C exception, so a session is never invalidated while it can still be used.
    private static var retiredSessions: [ObjectIdentifier: URLSession] = [:]

    /// URLSession getter that handles mTLS and SSL pinning if needed.
    ///
    /// A user-provided session (see `Harbor.setCustomURLSession`) is always used as-is and
    /// never replaced. Otherwise internally built sessions are cached per configuration and
    /// reused across requests so connections can be pooled; they are dropped when a
    /// session-affecting setting changes (see `invalidateURLSession()`).
    ///
    /// Attempts that create tasks on the session must use `leaseURLSession(for:)` instead,
    /// so the session cannot be invalidated while they hold it.
    /// - Parameter request: The request whose cache type and configuration select the session.
    static func getURLSession(for request: any HRequestBaseRequestProtocol) -> URLSession {
        if let customURLSession = HConfig.shared.customURLSession {
            return customURLSession
        }

        sessionUseTick &+= 1
        let signature = sessionSignature(for: request)
        if let cached = cachedSessions[signature] {
            cachedSessions[signature]?.lastUse = sessionUseTick
            return cached.session
        }

        if cachedSessions.count >= maxCachedSessions,
           let leastRecentlyUsed = cachedSessions.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            cachedSessions[leastRecentlyUsed.key] = nil
            retire(leastRecentlyUsed.value.session)
        }
        let session = buildURLSession(for: request)
        cachedSessions[signature] = CachedSession(session: session, lastUse: sessionUseTick)
        return session
    }

    /// Returns the session for the request and records that an attempt holds it. Until the
    /// matching `releaseURLSession(_:)`, the session is never invalidated: when it is dropped
    /// from the cache meanwhile (configuration change or eviction) it is only retired.
    /// - Parameter request: The request whose cache type and configuration select the session.
    /// - Returns: The session to create the attempt's tasks on.
    static func leaseURLSession(for request: any HRequestBaseRequestProtocol) -> URLSession {
        let session = getURLSession(for: request)
        sessionLeases[ObjectIdentifier(session), default: 0] += 1
        return session
    }

    /// Releases a session obtained with `leaseURLSession(for:)`. A retired session is
    /// invalidated once its last lease is released.
    /// - Parameter session: The leased session.
    static func releaseURLSession(_ session: URLSession) {
        let id = ObjectIdentifier(session)
        guard let leases = sessionLeases[id] else { return }
        guard leases <= 1 else {
            sessionLeases[id] = leases - 1
            return
        }
        sessionLeases[id] = nil
        retiredSessions.removeValue(forKey: id)?.finishTasksAndInvalidate()
    }

    /// Number of retired sessions still held by in-flight attempts. Intended for testing.
    static var retiredURLSessionCount: Int {
        retiredSessions.count
    }

    /// Drops the cached sessions so the next request builds one from the current configuration.
    /// Called by the `Harbor` configuration setters when session-affecting settings (timeouts,
    /// mTLS, SSL pinning, cookies, protocol classes) change. A user-provided session is never
    /// touched. Sessions still held by in-flight attempts are invalidated when those attempts
    /// release them.
    static func invalidateURLSession() {
        let sessions = cachedSessions.values.map(\.session)
        cachedSessions.removeAll()
        sessions.forEach(retire)
    }

    /// Invalidates a session dropped from the cache once no attempt holds it: immediately when
    /// it is not leased, otherwise when its last lease is released. Running tasks finish first.
    /// - Parameter session: The session dropped from the cache.
    private static func retire(_ session: URLSession) {
        let id = ObjectIdentifier(session)
        if sessionLeases[id] != nil {
            retiredSessions[id] = session
        } else {
            session.finishTasksAndInvalidate()
        }
    }

    /// Computes the signature that uniquely identifies the required session configuration for the given request.
    private static func sessionSignature(for request: any HRequestBaseRequestProtocol) -> SessionSignature {
        // Non-GET requests keep the configuration defaults (URLCache.shared with
        // .useProtocolCachePolicy). The signature must mirror what buildURLSession
        // installs so functionally identical configurations share one cached session.
        var cache: SessionSignature.CacheSignature = .urlCache(ObjectIdentifier(URLCache.shared), .useProtocolCachePolicy)
        if let getRequest = request as? any HGetRequestProtocol {
            switch getRequest.cacheType ?? HConfig.shared.cacheType {
            case .urlCache(let urlCache, let requestPolicy):
                cache = .urlCache(ObjectIdentifier(urlCache), requestPolicy)
            case .custom, .disabled:
                cache = .isolated
            }
        }

        return SessionSignature(cache: cache, httpShouldHandleCookies: HConfig.shared.httpShouldHandleCookies)
    }

    /// Builds a new URLSession tailored to the request's configuration. The session always
    /// gets an `HURLSessionDelegate`: besides SSL pinning and mTLS it strips credentials
    /// from cross-origin redirects.
    private static func buildURLSession(for request: any HRequestBaseRequestProtocol) -> URLSession {
        let configuration = URLSessionConfiguration.default
        // Each URLRequest carries its own timeout (see HURLBuilder); this is the fallback.
        configuration.timeoutIntervalForRequest = HConfig.shared.timeoutInterval
        // The whole-transfer limit is independent of the idle timeout. Leaving it unset keeps
        // the system default (7 days) so long transfers are not cut off.
        if let resourceTimeoutInterval = HConfig.shared.resourceTimeoutInterval {
            configuration.timeoutIntervalForResource = resourceTimeoutInterval
        }
        // Cookie handling is governed at the session-configuration level on Darwin; the
        // request-level flag set by HURLBuilder alone is not enough.
        configuration.httpShouldSetCookies = HConfig.shared.httpShouldHandleCookies

        if let protocolClasses = HConfig.shared.protocolClasses {
            configuration.protocolClasses = protocolClasses
        }

        // Only HGetRequestProtocol has cache. For cache types other than .urlCache, install an
        // isolated zero-capacity URLCache so responses are never served from — nor stored
        // into — URLCache.shared.
        if let getRequest = request as? any HGetRequestProtocol {
            let cacheType: HCache.CacheType = getRequest.cacheType ?? HConfig.shared.cacheType

            switch cacheType {
            case .urlCache(let cache, let requestPolicy):
                configuration.urlCache = cache
                configuration.requestCachePolicy = requestPolicy
            case .custom, .disabled:
                configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
            }
        }

        let sessionDelegate = HURLSessionDelegate(mTLSIdentity: HConfig.shared.mTLSIdentity,
                                                  sslPinningKeys: HConfig.shared.sslPinningKeys,
                                                  sslPinningKeysByHost: HConfig.shared.sslPinningKeysByHost)
        return URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
    }
}

// MARK: - Retry Loop Outcomes

/// Outcome of a single attempt in the retry loop. Carries the final response when the
/// loop should exit; otherwise signals a retry, a 401 that may be retried with refreshed
/// credentials, or (inside the attempt only) a `304` without a cached body that is
/// re-fetched unconditionally (`.refetchUnconditionally`).
private enum HAttemptOutcome<Response: Sendable> {
    /// The request is done; return the response to the caller.
    case finish(Response)
    /// The attempt failed in a retryable way; the loop runs another attempt after the given
    /// delay (from `Retry-After`), or after the policy's backoff when `nil`.
    case retry(after: TimeInterval?)
    /// The server rejected the credentials; the loop decides whether a refreshed header allows another attempt.
    case unauthorized
    /// A conditional request got `304` but no cached body exists; the attempt re-issues the
    /// request without validators. Consumed inside the attempt, never by the retry loop.
    case refetchUnconditionally
}

/// Outcome of evaluating a 401 response against the auth provider. The retry case carries
/// the refreshed authorization header, which the loop applies to the next attempt's
/// `URLRequest` without touching the request object.
private enum HAuthRefresh {
    /// The provider issued a different authorization header; retry with it applied.
    /// `notifiedProvider` tells whether `authFailed()` was called to obtain it.
    case retry(HAuthorizationHeader, notifiedProvider: Bool)
    /// No further attempt is possible; finish with the given error.
    case giveUp(HRequestError)
}

/// Whether a retryable status code may be retried once its `Retry-After` header is considered.
enum HStatusRetry: Equatable {
    /// Retry after the server-provided delay, or after the policy's backoff when `nil`.
    case retry(after: TimeInterval?)
    /// The server asked to wait longer than `HRetryPolicy.maxDelay`; the response is returned as-is.
    case giveUp
}
