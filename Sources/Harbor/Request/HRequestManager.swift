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
    /// after a 401. These attempts are ADDITIONAL to the retry policy's `maxAttempts` — they
    /// are not deducted from it. Worst-case total network calls per request are
    /// `retryPolicy.maxAttempts + maxAuthRetries`.
    static let maxAuthRetries = 1
}

// MARK: - Request With Result
extension HRequestManager {
    /// Executes a request that expects a typed model response.
    static func request<Model: HModel, Request: HRequestWithResultProtocol>(model: Model.Type, request: Request) async -> HResponseWithResult<Model> {
        let policy = request.retryPolicy

        if let mock = HMocker.mock(request: request), HConfig.shared.mocksEnabled {
            if let delay = mock.delay {
                await sleep(seconds: delay)
            }

            if let hError = mock.error {
                await logError(hError, request: request)
                return .error(hError)
            }

            let data = mock.jsonResponse?.data(using: .utf8) ?? Data()
            let mockResponse = HTTPURLResponse(url: mockURL(for: request), statusCode: mock.statusCode, httpVersion: nil, headerFields: mock.headers)
            return await runAttempts(
                request: request,
                policy: policy,
                errorResponse: { .error($0) }
            ) { currentRequest, canRetry in
                return await processResponse(model: model, request: currentRequest, statusCode: mock.statusCode, data: data, httpResponse: mockResponse, canRetry: canRetry)
            }
        }

        if !connectivityMonitor.isConnectedToNetwork() {
            if let getRequest = request as? any HGetRequestProtocol,
               let stale = await getRequest.staleCacheOnError() as? Model {
                return .success(stale)
            }
            let hError: HRequestError = .noConnection
            await logError(hError, request: request)
            return .error(hError)
        }

        switch await addAuthCredentialsIfNeeded(request) {
        case .failure(let hError):
            await logError(hError, request: request)
            return .error(hError)
        case .success(let authedRequest):
            return await runAttempts(
                request: authedRequest,
                policy: policy,
                errorResponse: { .error($0) }
            ) { currentRequest, canRetry in
                return await executeOnce(model: model, request: currentRequest, canRetry: canRetry)
            }
        }
    }

    /// Executes a single network attempt: builds the URLRequest, performs the call and
    /// processes the response. `canRetry` tells whether the loop can run another attempt,
    /// so retryable failures are reported as `.retry` only while attempts remain.
    private static func executeOnce<Model: HModel, Request: HRequestWithResultProtocol>(model: Model.Type, request: Request, canRetry: Bool) async -> HAttemptOutcome<HResponseWithResult<Model>> {
        let urlRequest: URLRequest
        do {
            urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
        } catch let hError as HRequestError {
            await logError(hError, request: request)
            return .finish(.error(hError))
        } catch {
            let hError: HRequestError = .malformedRequest(reason: String(describing: error))
            await logError(hError, request: request)
            return .finish(.error(hError))
        }

        if let request = request as? HDebugRequestProtocol {
            await request.logRequest(urlRequest: urlRequest)
        }

        let session = getURLSession(for: request)
        let startTime = Date()

        do {
            let (data, httpResponse) = try await session.data(for: urlRequest)

            let duration = Date().timeIntervalSince(startTime) * 1000

            guard let httpResponse = httpResponse as? HTTPURLResponse else {
                if canRetry {
                    return .retry
                }
                let hError: HRequestError = .invalidHttpResponse
                await logError(hError, request: request)
                return .finish(.error(hError))
            }

            if let request = request as? HDebugRequestProtocol {
                await request.logResponse(httpResponse: httpResponse, data: data, duration: duration)
            }

            return await processResponse(model: model,
                                         request: request,
                                         statusCode: httpResponse.statusCode,
                                         data: data,
                                         httpResponse: httpResponse,
                                         canRetry: canRetry)
        } catch let error as URLError {
            let isCancelled = error.code == .cancelled || Task.isCancelled
            if !isCancelled,
               let getRequest = request as? any HGetRequestProtocol,
               let stale = await getRequest.staleCacheOnError() as? Model {
                return .finish(.success(stale))
            }
            let hError = HRequestError.mapURLError(error)
            if canRetry, !isCancelled {
                return .retry
            }
            await logError(hError, request: request)
            return .finish(.error(hError))
        } catch {
            if canRetry, !Task.isCancelled {
                return .retry
            }
            // Distinguish cancellation from a genuine programming error: when the task was
            // cancelled mid-attempt the generic catch can fire (e.g. via a cancelled
            // continuation) and we must surface `.cancelled`, not `.invalidRequest`.
            let hError: HRequestError = Task.isCancelled ? .cancelled : .invalidRequest
            await logError(hError, request: request)
            return .finish(.error(hError))
        }
    }

    /// Processes the raw response for a model-returning request, decoding the payload or handling errors/revalidation.
    private static func processResponse<Model: HModel, Request: HRequestWithResultProtocol>(model: Model.Type, request: Request, statusCode: Int, data: Data, httpResponse: HTTPURLResponse? = nil, canRetry: Bool = false) async -> HAttemptOutcome<HResponseWithResult<Model>> {
        switch statusCode {
        case 200 ... 299:
            do {
                let parsedResponse = try request.parseData(data: data, model: model)

                if let request = request as? any HGetRequestProtocol {
                    await request.saveCache(data, response: httpResponse)
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
               let cachedAny = await getRequest.revalidatedCache(response: httpResponse),
               let cachedModel = cachedAny as? Model {
                return .finish(.success(cachedModel))
            } else {
                let hError: HRequestError = .api(statusCode: statusCode, data: data)
                await logError(hError, request: request)
                return .finish(.error(hError))
            }
        case 401:
            return .unauthorized
        default:
            if canRetry {
                return .retry
            }
            if statusCode >= 500,
               let getRequest = request as? any HGetRequestProtocol,
               let stale = await getRequest.staleCacheOnError() as? Model {
                return .finish(.success(stale))
            }
            let hError: HRequestError = .api(statusCode: statusCode, data: data)
            await logError(hError, request: request)
            return .finish(.error(hError))
        }
    }
}

// MARK: - Request Without Result
extension HRequestManager {
    /// Executes a request that expects an empty response.
    static func request<Request: HRequestWithEmptyResponseProtocol>(request: Request) async -> HResponse {
        let policy = request.retryPolicy

        if let mock = HMocker.mock(request: request), HConfig.shared.mocksEnabled {
            if let delay = mock.delay {
                await sleep(seconds: delay)
            }

            if let hError = mock.error {
                await logError(hError, request: request)
                return .error(hError)
            }

            let data = mock.jsonResponse?.data(using: .utf8) ?? Data()
            return await runAttempts(
                request: request,
                policy: policy,
                errorResponse: { .error($0) }
            ) { currentRequest, canRetry in
                return await processResponse(request: currentRequest, statusCode: mock.statusCode, data: data, canRetry: canRetry)
            }
        }

        if !connectivityMonitor.isConnectedToNetwork() {
            let hError: HRequestError = .noConnection
            await logError(hError, request: request)
            return .error(hError)
        }

        switch await addAuthCredentialsIfNeeded(request) {
        case .failure(let hError):
            await logError(hError, request: request)
            return .error(hError)
        case .success(let authedRequest):
            return await runAttempts(
                request: authedRequest,
                policy: policy,
                errorResponse: { .error($0) }
            ) { currentRequest, canRetry in
                return await executeOnce(request: currentRequest, canRetry: canRetry)
            }
        }
    }

    /// Executes a single network attempt: builds the URLRequest, performs the call and
    /// processes the response. `canRetry` tells whether the loop can run another attempt,
    /// so retryable failures are reported as `.retry` only while attempts remain.
    private static func executeOnce<Request: HRequestWithEmptyResponseProtocol>(request: Request, canRetry: Bool) async -> HAttemptOutcome<HResponse> {
        let urlRequest: URLRequest
        do {
            urlRequest = try await HURLBuilder.buildUrlRequest(request: request)
        } catch let hError as HRequestError {
            await logError(hError, request: request)
            return .finish(.error(hError))
        } catch {
            let hError: HRequestError = .malformedRequest(reason: String(describing: error))
            await logError(hError, request: request)
            return .finish(.error(hError))
        }

        if let request = request as? HDebugRequestProtocol {
            await request.logRequest(urlRequest: urlRequest)
        }

        let session = getURLSession(for: request)
        let startTime = Date()

        do {
            let (data, httpResponse) = try await session.data(for: urlRequest)

            let duration = Date().timeIntervalSince(startTime) * 1000

            guard let httpResponse = httpResponse as? HTTPURLResponse else {
                if canRetry {
                    return .retry
                }
                let hError: HRequestError = .invalidHttpResponse
                await logError(hError, request: request)
                return .finish(.error(hError))
            }

            if let request = request as? HDebugRequestProtocol {
                await request.logResponse(httpResponse: httpResponse, data: data, duration: duration)
            }

            return await processResponse(request: request, statusCode: httpResponse.statusCode, data: data, canRetry: canRetry)
        } catch let error as URLError {
            let hError = HRequestError.mapURLError(error)
            let isCancelled = error.code == .cancelled || Task.isCancelled
            if canRetry, !isCancelled {
                return .retry
            }
            await logError(hError, request: request)
            return .finish(.error(hError))
        } catch {
            if canRetry, !Task.isCancelled {
                return .retry
            }
            let hError: HRequestError = Task.isCancelled ? .cancelled : .invalidRequest
            await logError(hError, request: request)
            return .finish(.error(hError))
        }
    }

    /// Processes the raw response for an empty-response request, checking status codes and handling errors.
    private static func processResponse<Request: HRequestWithEmptyResponseProtocol>(request: Request, statusCode: Int, data: Data, canRetry: Bool = false) async -> HAttemptOutcome<HResponse> {
        switch statusCode {
        case 200 ... 299:
            return .finish(.success)
        case 304:
            // Not Modified — the cached representation is still valid; there is no body to serve.
            return .finish(.success)
        case 401:
            return .unauthorized
        default:
            if canRetry {
                return .retry
            }
            let hError: HRequestError = .api(statusCode: statusCode, data: data)
            await logError(hError, request: request)
            return .finish(.error(hError))
        }
    }
}

// MARK: - Request Builder Functions
extension HRequestManager {
    /// Runs the retry loop, delegating each attempt to `executeAttempt`. Mocks, connectivity
    /// checks and the initial auth injection are evaluated once by the caller, not per attempt.
    /// `errorResponse` builds the typed response for the cancellation and auth-giveup paths.
    ///
    /// `TypedRequest` preserves the concrete request type from the caller through the loop,
    /// so the executor closure receives the typed request without any existential cast.
    private static func runAttempts<TypedRequest: HRequestBaseRequestProtocol & Sendable, Response: Sendable>(
        request: TypedRequest,
        policy: HRetryPolicy?,
        errorResponse: @escaping (HRequestError) -> Response,
        executeAttempt: @escaping (TypedRequest, Bool) async -> HAttemptOutcome<Response>
    ) async -> Response {
        var currentRequest = request
        var attempt = 1
        var authRetriesRemaining = maxAuthRetries
        let maxAttempts = policy?.maxAttempts ?? 1

        while true {
            guard !Task.isCancelled else {
                let hError: HRequestError = .cancelled
                await logError(hError, request: currentRequest)
                return errorResponse(hError)
            }

            if attempt > 1, let policy {
                await sleep(seconds: policy.delay(forRetry: attempt - 1))
            }

            let canRetry = attempt < maxAttempts

            switch await executeAttempt(currentRequest, canRetry) {
            case .finish(let response):
                return response
            case .retry:
                attempt += 1
            case .unauthorized:
                switch await refreshAuthorization(for: currentRequest, authRetriesRemaining: authRetriesRemaining) {
                case .retry(let refreshedRequest):
                    currentRequest = refreshedRequest
                    authRetriesRemaining -= 1
                case .giveUp(let hError):
                    await logError(hError, request: currentRequest)
                    return errorResponse(hError)
                }
            }
        }
    }

    /// Injects the provider's authorization header into requests that need auth.
    /// Fails with `.authProviderNeeded` when no provider is configured and with
    /// `.malformedRequest` when the request type does not persist header parameters,
    /// which would otherwise send the request out unauthenticated.
    ///
    /// Generic over the request type so the caller preserves the concrete type and avoids
    /// casting back through an existential.
    static func addAuthCredentialsIfNeeded<P: HRequestBaseRequestProtocol>(_ request: P) async -> Result<P, HRequestError> {
        guard request.needsAuth else { return .success(request) }

        guard let authCredential = await HConfig.shared.authProvider?.getAuthorizationHeader() else {
            return .failure(.authProviderNeeded)
        }

        var modifiedRequest = request
        if modifiedRequest.headerParameters == nil {
            modifiedRequest.headerParameters = [:]
        }
        modifiedRequest.headerParameters?[authCredential.key] = authCredential.value

        guard modifiedRequest.headerParameters?[authCredential.key] == authCredential.value else {
            return .failure(.malformedRequest(reason: "The request type does not persist header parameters"))
        }

        return .success(modifiedRequest)
    }

    /// Fetches the provider's authorization header once and compares it with the one the
    /// failed attempt used. A retry is offered only when auth attempts remain and the
    /// provider issued a different header. If the previously-injected header is absent the
    /// request type does not persist headers (programming error) and we surface it loudly
    /// instead of returning `.authNeeded`, which would hide the real cause.
    private static func refreshAuthorization<P: HRequestBaseRequestProtocol>(
        for request: P,
        authRetriesRemaining: Int
    ) async -> HAuthRefresh<P> {
        guard authRetriesRemaining > 0, let authProvider = HConfig.shared.authProvider else {
            await HConfig.shared.authProvider?.authFailed()
            return .giveUp(.authNeeded)
        }

        let freshHeader = await authProvider.getAuthorizationHeader()

        guard let usedAuthorization = request.headerParameters?[freshHeader.key] else {
            // The header slot is missing: the request type's setter is a no-op (the loud-failure
            // path of `addAuthCredentialsIfNeeded` should have caught this earlier, but a
            // conformer that drops the value between attempts is still possible).
            return .giveUp(.malformedRequest(reason: "The request type does not persist header parameters"))
        }

        guard usedAuthorization != freshHeader.value else {
            await authProvider.authFailed()
            return .giveUp(.authNeeded)
        }

        var modifiedRequest = request
        if modifiedRequest.headerParameters == nil {
            modifiedRequest.headerParameters = [:]
        }
        modifiedRequest.headerParameters?[freshHeader.key] = freshHeader.value

        guard modifiedRequest.headerParameters?[freshHeader.key] == freshHeader.value else {
            // The request type does not persist header parameters, so the fresh credentials would go out missing.
            return .giveUp(.malformedRequest(reason: "The request type does not persist header parameters"))
        }

        return .retry(modifiedRequest)
    }



    /// Sleeps for the given number of seconds. Negative values are treated as zero and the
    /// delay is clamped to `HRetryPolicy.maxDelay` before converting to nanoseconds.
    static func sleep(seconds: TimeInterval) async {
        let clampedSeconds = min(max(seconds, 0), HRetryPolicy.maxDelay)
        guard clampedSeconds > 0 else { return }
        if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
            try? await Task.sleep(for: .seconds(clampedSeconds))
        } else {
            try? await Task.sleep(nanoseconds: UInt64(clampedSeconds * 1_000_000_000))
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
    static func logError(_ error: HRequestError, request: HRequestBaseRequestProtocol) async {
        if let request = request as? HDebugRequestProtocol {
            await request.logErrorResponse(error: error)
        }
    }
}

// MARK: - URLSession Management
extension HRequestManager {
    /// Inputs that differentiate internally built sessions; a change in any of them requires a new session.
    private struct SessionSignature: Equatable {
        enum CacheSignature: Equatable {
            case isolated
            case urlCache(ObjectIdentifier, URLRequest.CachePolicy)
        }
        /// The timeout interval for the session.
        var timeoutInterval: TimeInterval
        /// The cache configuration for the session.
        var cache: CacheSignature
    }

    /// The currently cached URLSession for reuse.
    private static var cachedSession: URLSession?
    /// The signature of the currently cached session.
    private static var cachedSessionSignature: SessionSignature?

    /// URLSession getter that handles mTLS and SSL pinning if needed.
    ///
    /// A user-provided session (see `Harbor.setCustomURLSession`) is always used as-is and
    /// never replaced. Otherwise the internally built session is cached and reused across
    /// requests so connections can be pooled; it is rebuilt when the configuration or the
    /// per-request session inputs change.
    static func getURLSession(for request: any HRequestBaseRequestProtocol) -> URLSession {
        if let customURLSession = HConfig.shared.customURLSession {
            return customURLSession
        }

        let signature = sessionSignature(for: request)
        if let cachedSession, cachedSessionSignature == signature {
            return cachedSession
        }

        let session = buildURLSession(for: request)
        if let cachedSession {
            cachedSession.finishTasksAndInvalidate()
        }
        cachedSession = session
        cachedSessionSignature = signature
        return session
    }

    /// Drops the cached session so the next request builds one from the current configuration.
    /// Called by `HConfig` when session-affecting settings (timeout, mTLS, SSL pinning,
    /// protocol classes) change. A user-provided session is never touched.
    static func invalidateURLSession() {
        cachedSession?.finishTasksAndInvalidate()
        cachedSession = nil
        cachedSessionSignature = nil
    }

    /// Computes the signature that uniquely identifies the required session configuration for the given request.
    private static func sessionSignature(for request: any HRequestBaseRequestProtocol) -> SessionSignature {
        let timeoutInterval = request.timeoutInterval ?? HConfig.shared.timeoutInterval

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

        return SessionSignature(timeoutInterval: timeoutInterval, cache: cache)
    }

    /// Builds a new URLSession tailored to the request's configuration.
    private static func buildURLSession(for request: any HRequestBaseRequestProtocol) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = request.timeoutInterval ?? HConfig.shared.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval ?? HConfig.shared.timeoutInterval

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

        // If mTLS or SSL pinning is configured, the session needs a delegate to validate challenges.
        if HConfig.shared.mTLSIdentity != nil || HConfig.shared.sslPinningKeys != nil {
            let sessionDelegate = HURLSessionDelegate(mTLSIdentity: HConfig.shared.mTLSIdentity,
                                                      sslPinningKeys: HConfig.shared.sslPinningKeys)
            return URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
        }

        return URLSession(configuration: configuration)
    }
}

// MARK: - Retry Loop Outcomes

/// Outcome of a single attempt in the retry loop. Carries the final response when the
/// loop should exit; otherwise signals a retry or a 401 that may be retried with
/// refreshed credentials.
private enum HAttemptOutcome<Response: Sendable> {
    /// The request is done; return the response to the caller.
    case finish(Response)
    /// The attempt failed in a retryable way; the loop runs another attempt.
    case retry
    /// The server rejected the credentials; the loop decides whether a refreshed header allows another attempt.
    case unauthorized
}

/// Outcome of evaluating a 401 response against the auth provider. The retry case carries
/// the request with the refreshed header applied, preserving the concrete request type so
/// the loop does not need to cast back through an existential.
private enum HAuthRefresh<Request: HRequestBaseRequestProtocol> {
    /// The provider issued a different authorization header; retry with it applied to the request.
    case retry(Request)
    /// No further attempt is possible; finish with the given error.
    case giveUp(HRequestError)
}
