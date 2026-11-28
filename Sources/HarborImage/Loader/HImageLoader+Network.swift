//
//  HImageLoader+Network.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

// MARK: - Download

/// Downloaded image bytes.
struct HImageDownload: Sendable {
    /// The bytes.
    let data: Data
    /// `.network`, or `.local` for a mock.
    let source: HImageSource
    /// Whether the bytes must not be stored on disk: `Cache-Control: no-store`, or a mock.
    let forbidsStorage: Bool
}

extension HImageLoader {
    /// Downloads the bytes of one URL, sharing the download with every concurrent load of the
    /// same URL and headers (image loads and byte loads alike). A registered mock (debug builds)
    /// answers instead, without auth, retries, download slots nor size limit.
    /// - Parameters:
    ///   - url: The URL.
    ///   - resolved: The request; the first one of a shared download sets its headers, auth,
    ///     retry policy and timeout.
    ///   - onEvent: Receives the progress and retry events.
    static func sharedDownload(url: URL, resolved: HImageResolvedRequest, onEvent: @escaping HImageEventSink) async -> Result<HImageDownload, HImageError> {
        if let mocked = await mockedDownload(url: url) {
            return mocked
        }
        let key = downloadKey(url: url, resolved: resolved)
        for _ in 0..<2 {
            let flight: HImageFlight<Result<HImageDownload, HImageError>>
            if let existing = downloadFlights[key], !existing.isAbandoned {
                flight = existing
            } else {
                flight = HImageFlight(cancelledResponse: .failure(.cancelled))
                downloadFlights[key] = flight
                flight.attach(Task {
                    let result = await download(url: url, resolved: resolved) { flight.broadcast($0) }
                    if downloadFlights[key] === flight {
                        downloadFlights[key] = nil
                    }
                    flight.finish(result)
                })
            }
            guard let id = flight.subscribe(sink: onEvent) else { continue }
            return await flight.wait(id: id)
        }
        return .failure(.cancelled)
    }

    /// Identifies a download: what changes the request sent (URL, headers, auth, timeout) and
    /// the generations, so a load that starts after the cache was cleared, the auth provider
    /// replaced or the image stored never receives bytes fetched before.
    /// - Parameters:
    ///   - url: The URL.
    ///   - resolved: The request.
    private static func downloadKey(url: URL, resolved: HImageResolvedRequest) -> String {
        let request = resolved.request
        let headers = (request.headerParameters ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        return [Generation.current(for: resolved.key.original).identifier,
                url.absoluteString,
                String(request.needsAuth),
                request.timeoutInterval.map { String($0) } ?? "-"]
            .joined(separator: "|") + "|" + headers.joined(separator: "&")
    }

    /// Downloads the bytes of one URL through Harbor's shared pipeline: a download slot, auth
    /// with the `401` refresh flow, retries with `Retry-After`, the session pool (pinning, mTLS,
    /// redirects) and the size limit.
    /// - Parameters:
    ///   - url: The URL.
    ///   - resolved: The request.
    ///   - onEvent: Receives the progress and retry events.
    private static func download(url: URL, resolved: HImageResolvedRequest, onEvent: @escaping HImageEventSink) async -> Result<HImageDownload, HImageError> {
        // The slot first, so the authorization header is read when the download can start and
        // not before a long wait, when it may have expired.
        guard await limiter.acquire(limit: HImageConfig.shared.maxConcurrentDownloads) else {
            return .failure(.cancelled)
        }
        defer { limiter.release() }

        let request = resolved.request
        let authHeader: HAuthorizationHeader?
        switch await HRequestManager.authorizationHeader(needsAuth: request.needsAuth) {
        case .failure(let error):
            return .failure(HImageError(pipelineError: error))
        case .success(let header):
            authHeader = header
        }

        var attempts = 0
        return await HRequestManager.runAttemptLoop(
            needsAuth: request.needsAuth,
            retryPolicy: resolved.retryPolicy,
            authHeader: authHeader,
            failWith: { error in .failure(HImageError(pipelineError: error)) }
        ) { currentAuthHeader, canRetry in
            attempts += 1
            if attempts > 1 {
                onEvent(.retrying(attempt: attempts - 1))
            }
            return await attempt(url: url, resolved: resolved, authHeader: currentAuthHeader, canRetry: canRetry, onEvent: onEvent)
        }
    }

    /// Performs one download attempt on a leased session.
    /// - Parameters:
    ///   - url: The URL.
    ///   - resolved: The request.
    ///   - authHeader: The authorization header to send, if any.
    ///   - canRetry: Whether the loop can run another attempt.
    ///   - onEvent: Receives the progress events.
    private static func attempt(url: URL, resolved: HImageResolvedRequest, authHeader: HAuthorizationHeader?, canRetry: Bool, onEvent: @escaping HImageEventSink) async -> HAttemptOutcome<Result<HImageDownload, HImageError>> {
        let maxBytes = HImageConfig.shared.maxDownloadSizeInBytes
        let urlRequest = urlRequest(url: url, request: resolved.request, authHeader: authHeader)
        let session = HRequestManager.leaseURLSession(profile: .isolated)
        defer { HRequestManager.releaseURLSession(session) }

        let delegate = HImageDownloadDelegate(authHeaderKey: authHeader?.key, maxBytes: maxBytes) { onEvent(.progress($0)) }
        let task = session.dataTask(with: urlRequest)
        task.delegate = delegate
        task.resume()
        let completion = await withTaskCancellationHandler {
            await delegate.waitForCompletion()
        } onCancel: {
            task.cancel()
        }

        if completion.exceededLimit {
            return .finish(.failure(.tooLarge(maxBytes: maxBytes)))
        }
        if let error = completion.error {
            return failureOutcome(error, trustEvaluationFailed: completion.trustEvaluationFailed, retryPolicy: resolved.retryPolicy, canRetry: canRetry)
        }
        guard let response = completion.response else {
            return .finish(.failure(.network(URLError(.badServerResponse))))
        }

        let statusCode = response.statusCode
        if (200...299).contains(statusCode) {
            let cacheControl = response.value(forHTTPHeaderField: "Cache-Control")?.lowercased() ?? ""
            return .finish(.success(HImageDownload(data: completion.data, source: .network, forbidsStorage: cacheControl.contains("no-store"))))
        }
        if statusCode == 401 {
            return .unauthorized
        }
        if canRetry, resolved.retryPolicy?.shouldRetry(statusCode: statusCode, isIdempotent: true) == true,
           case .retry(let retryAfter) = HRequestManager.statusRetry(statusCode: statusCode, httpResponse: response) {
            return .retry(after: retryAfter)
        }
        return .finish(.failure(.api(statusCode: statusCode)))
    }

    /// Classifies a transport error: a rejected TLS challenge is `.certificate`, never retried;
    /// retryable errors honor the retry policy.
    /// - Parameters:
    ///   - error: The error the task completed with.
    ///   - trustEvaluationFailed: Whether Harbor's delegate rejected a TLS challenge.
    ///   - retryPolicy: The retry policy.
    ///   - canRetry: Whether the loop can run another attempt.
    private static func failureOutcome(_ error: Error, trustEvaluationFailed: Bool, retryPolicy: HRetryPolicy?, canRetry: Bool) -> HAttemptOutcome<Result<HImageDownload, HImageError>> {
        guard let urlError = error as? URLError else {
            return .finish(.failure(HImageError(pipelineError: HRequestManager.mapNonURLError(error))))
        }
        let mapped = HRequestManager.mapTransportError(urlError, trustEvaluationFailed: trustEvaluationFailed)
        if mapped != .certificate, mapped != .cancelled, canRetry,
           retryPolicy?.shouldRetry(urlError: urlError, isIdempotent: true) == true {
            return .retry(after: nil)
        }
        return .finish(.failure(HImageError(pipelineError: mapped)))
    }

    /// Builds the download request: timeout, cookie flag, `Harbor`'s default headers, the request
    /// headers, an image `Accept` header unless one was given, and the authorization header.
    /// - Parameters:
    ///   - url: The URL.
    ///   - request: The image request.
    ///   - authHeader: The authorization header to send, if any.
    static func urlRequest(url: URL, request: any HImageRequestProtocol, authHeader: HAuthorizationHeader?) -> URLRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = request.timeoutInterval ?? HConfig.shared.timeoutInterval
        urlRequest.httpShouldHandleCookies = HConfig.shared.httpShouldHandleCookies
        urlRequest.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")

        for (key, value) in HConfig.shared.defaultHeaderParameters ?? [:] {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        for (key, value) in request.headerParameters ?? [:] {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if let authHeader {
            urlRequest.setValue(authHeader.value, forHTTPHeaderField: authHeader.key)
            // Redact the provider's header in debug output even under a non-standard name.
            HRedactionPolicy.registerAuthHeaderKey(authHeader.key)
        }
        return urlRequest
    }
}

// MARK: - Mocks and Local URLs

extension HImageLoader {
    /// Whether a registered mock answers one of the request's URLs (debug builds, mocks
    /// enabled). Such a load skips the disk cache and the connectivity check.
    /// - Parameter resolved: The request.
    static func isMocked(_ resolved: HImageResolvedRequest) -> Bool {
        guard HBuild.isDebug, HImageConfig.shared.mocksEnabled else { return false }
        return resolved.urls.contains { HImageConfig.shared.mocks[$0.absoluteString] != nil }
    }

    /// The answer of a registered mock for the URL, in debug builds with mocks enabled.
    /// - Parameter url: The composed URL.
    private static func mockedDownload(url: URL) async -> Result<HImageDownload, HImageError>? {
        guard HBuild.isDebug, HImageConfig.shared.mocksEnabled, let mock = HImageConfig.shared.mocks[url.absoluteString] else {
            return nil
        }
        if mock.delay > 0, !(await HRequestManager.sleep(seconds: mock.delay)) {
            return .failure(.cancelled)
        }
        guard let data = mock.data else { return .failure(mock.error) }
        return .success(HImageDownload(data: data, source: .local, forbidsStorage: true))
    }

    /// Reads the bytes of a `data:` or `file:` URL, off the actor.
    /// - Parameter url: The URL.
    nonisolated static func localData(_ url: URL) async -> Result<Data, HImageError> {
        if url.isFileURL {
            do {
                return .success(try Data(contentsOf: url, options: .mappedIfSafe))
            } catch {
                return .failure(.invalidURL(reason: "The file cannot be read"))
            }
        }
        let text = url.absoluteString
        guard let comma = text.firstIndex(of: ",") else {
            return .failure(.invalidURL(reason: "Invalid data URL"))
        }
        let header = text[text.index(text.startIndex, offsetBy: 5)..<comma].lowercased()
        let payload = String(text[text.index(after: comma)...])
        let decoded = payload.removingPercentEncoding ?? payload
        if header.hasSuffix(";base64") {
            guard let data = Data(base64Encoded: decoded, options: .ignoreUnknownCharacters) else {
                return .failure(.invalidURL(reason: "Invalid base64 in data URL"))
            }
            return .success(data)
        }
        return .success(Data(decoded.utf8))
    }
}
