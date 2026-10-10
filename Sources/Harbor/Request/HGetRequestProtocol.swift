//
//  HGetRequestProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - GET Request Protocol
/// A GET request: decoded into `Model`, cacheable, and streamable from cache and network.
///
/// ```swift
/// struct GetUserRequest: HGetRequestProtocol {
///     typealias Model = User
///     let userId: Int
///     let url = "https://api.example.com/users/{id}"
///     var pathParameters: [String: String]? { ["id": String(userId)] }
/// }
///
/// switch await GetUserRequest(userId: 1).request() {
/// case .success(let user): print(user.name)
/// case .error(let error): print(error)
/// }
/// ```
public protocol HGetRequestProtocol: HRequestWithResultProtocol {
    /// Query parameters appended to the URL, strictly percent-encoded (`+` is sent as `%2B`).
    /// Default: `nil`.
    var queryParameters: [String: String]? { get }
    /// The cache used by this request. Default: `nil` (the type set with
    /// `Harbor.setDefaultCacheType(_:)`, `.urlCache()` unless changed).
    var cacheType: HCache.CacheType? { get }
    /// Whether a successful response with this status code is stored in the cache. Return `false`
    /// for answers that are not the resource yet, such as a `202 Accepted` while the server is
    /// still preparing it: storing it would replace the good copy a later offline read needs.
    /// Default: `true`.
    func shouldCache(statusCode: Int) -> Bool
}

// MARK: - Default Implementations

/// Default implementations for `HGetRequestProtocol`.
public extension HGetRequestProtocol {
    /// The HTTP method for GET requests is `.get`.
    var httpMethod: HHttpMethod { .get }
    /// Default: `nil`.
    var queryParameters: [String: String]? { nil }
    /// Default: `nil`.
    var cacheType: HCache.CacheType? { nil }
    /// Default: `true`.
    func shouldCache(statusCode: Int) -> Bool { true }

    /// Streams the cached and/or the remote response of this request: at most one element from
    /// the cache (served under the rules of `cache()`) and one from the network, each tagged
    /// with its origin. The stream throws the `HRequestError` of a failed remote request, even
    /// after yielding a cached element. Cancelling the consuming task cancels the request.
    /// - Parameter source: Where to read from. Default: `.cacheAndRemote`.
    /// - Returns: A stream of `(response, origin)` elements.
    func requestStream(source: HRequestSource = .cacheAndRemote) -> AsyncThrowingStream<(response: Model, origin: HOriginType), Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                await self.handleStreamRequest(source: source, continuation: continuation)
            }
            // Cancelling the consumer cancels the task running the underlying request.
            continuation.onTermination = { @Sendable reason in
                if case .cancelled = reason {
                    task.cancel()
                }
            }
        }
    }

    /// Internal handler for stream request logic. Every path finishes the continuation exactly once.
    private func handleStreamRequest(
        source: HRequestSource,
        continuation: AsyncThrowingStream<(response: Model, origin: HOriginType), Error>.Continuation
    ) async {
        switch source {
        case .cacheOnly:
            if let cachedData = await cache() {
                continuation.yield((response: cachedData, origin: .cache))
                continuation.finish()
            } else {
                continuation.finish(throwing: HRequestError.noCachedDataFound)
            }

        case .remoteOnly:
            let (remoteResult, origin) = await requestTaggingFallback()
            switch remoteResult {
            case .success(let data):
                continuation.yield((response: data, origin: origin))
                continuation.finish()
            case .error(let error):
                continuation.finish(throwing: error)
            }

        case .cacheAndRemote:
            var yieldedCache = false
            if let cachedData = await cache() {
                continuation.yield((response: cachedData, origin: .cache))
                yieldedCache = true
            }

            let (remoteResult, origin) = await requestTaggingFallback()
            switch remoteResult {
            case .success(let data):
                // A cached copy that stood in for the network is the one just yielded: at most one cached element.
                if !(yieldedCache && origin == .cache) {
                    continuation.yield((response: data, origin: origin))
                }
                continuation.finish()
            case .error(let error):
                continuation.finish(throwing: error)
            }
        }
    }

    /// Runs the request and says where its answer came from: `.cache` when the network could not
    /// answer and a cached copy stood in for it (offline, or `stale-if-error`), `.remote` otherwise.
    private func requestTaggingFallback() async -> (HResponseWithResult<Model>, HOriginType) {
        let probe = HCacheFallbackProbe()
        let result = await HCacheFallbackProbe.$current.withValue(probe) { await self.request() }
        return (result, probe.wasServedFromCache ? .cache : .remote)
    }
}
