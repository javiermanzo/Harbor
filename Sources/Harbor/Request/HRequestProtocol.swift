//
//  HRequestProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - HModel
/// Type alias for models used in network requests. Must be `Codable & Sendable`.
public typealias HModel = Codable & Sendable

// MARK: - Request Source
/// Where `requestStream(source:)` reads from.
public enum HRequestSource: Sendable {
    /// Only the network: yields the remote response.
    case remoteOnly
    /// Only the cache, without a network request: yields the cached response, or throws
    /// `HRequestError.noCachedDataFound`.
    case cacheOnly
    /// The cache, then the network: yields the cached response first when there is one, then
    /// always the remote response.
    case cacheAndRemote
}

// MARK: - Origin Type
/// Where an element yielded by `requestStream(source:)` came from.
public enum HOriginType: Sendable {
    /// Data came from local cache.
    case cache
    /// Data came from remote server.
    case remote
}

// MARK: - Base Protocol
/// The requirements shared by every REST request. Conform to one of the method protocols
/// instead (`HGetRequestProtocol`, `HPostRequestProtocol`, `HPutRequestProtocol`,
/// `HPatchRequestProtocol`, `HDeleteRequestProtocol`); only `url` (plus `Model` for GET and
/// `bodyParameters` for body requests) has no default.
public protocol HRequestBaseRequestProtocol: Sendable {
    /// The endpoint URL. It may contain `{name}` placeholders replaced by `pathParameters`.
    var url: String { get }
    /// The HTTP method. Provided by the method protocol the request conforms to.
    var httpMethod: HHttpMethod { get }
    /// Whether the request carries the header of the auth provider set with
    /// `Harbor.setAuthProvider(_:)`, and goes through its refresh flow on a `401`. Default: `false`.
    var needsAuth: Bool { get }
    /// Optional retry policy for transient failures (retryable status codes and network
    /// errors, with backoff, jitter and `Retry-After` support). Default: `nil`.
    /// When `nil`, no retries are performed. See `HRetryPolicy` for what is retried.
    var retryPolicy: HRetryPolicy? { get }
    /// Values for the `{name}` placeholders of `url`. They are percent-encoded (`/` included), and
    /// a value containing a `..` segment fails with `.malformedRequest(reason:)`. Default: `nil`.
    var pathParameters: [String: String]? { get }
    /// Additional HTTP headers, applied on top of `Harbor`'s default headers (they win on a
    /// name clash, compared case-insensitively). Default: `nil`.
    var headerParameters: [String: String]? { get }
    /// Idle timeout for this request, in seconds. Default: `nil` (the value set with
    /// `Harbor.setDefaultTimeoutInterval(_:)`, 15 seconds unless changed).
    var timeoutInterval: TimeInterval? { get }
}

/// Default implementations for `HRequestBaseRequestProtocol`.
public extension HRequestBaseRequestProtocol {
    /// Default: `false`.
    var needsAuth: Bool { false }
    /// Default: `nil`.
    var retryPolicy: HRetryPolicy? { nil }
    /// Default: `nil`.
    var pathParameters: [String: String]? { nil }
    /// Default: `nil`.
    var headerParameters: [String: String]? { nil }
    /// Default: `nil`.
    var timeoutInterval: TimeInterval? { nil }
}

// MARK: - Request with Empty Result Protocol
/// A request whose response body is not decoded: it reports success or an `HRequestError`.
public protocol HRequestWithEmptyResponseProtocol: HRequestBaseRequestProtocol {
    /// Sends the request. Never throws: failures are returned as `.error`. Cancelling the
    /// calling `Task` cancels the request (`.error(.cancelled)`).
    /// - Returns: `.success` for a 2xx response, or `.error` with the reason it failed.
    func request() async -> HResponse
}

/// Default implementation for `HRequestWithEmptyResponseProtocol`.
public extension HRequestWithEmptyResponseProtocol {
    /// Default implementation that routes through `HRequestManager`.
    func request() async -> HResponse {
        return await HRequestManager.request(request: self)
    }
}

// MARK: - Request with Result Protocol
/// A request whose response body is decoded into `Model`.
public protocol HRequestWithResultProtocol: HRequestBaseRequestProtocol {
    /// The type the response body is decoded into.
    associatedtype Model: HModel
    /// Decodes a response body. Override it to unwrap an envelope or use a custom decoder; it
    /// is also used to decode cached bodies. Default: `JSONDecoder`.
    /// - Parameters:
    ///   - data: The raw data received from the response.
    ///   - model: The model type to decode.
    /// - Returns: The decoded model instance.
    /// - Throws: Decoding error if data cannot be parsed.
    func parseData<T: Codable>(data: Data, model: T.Type) throws -> T
    /// Sends the request and decodes the response. Never throws: failures are returned as
    /// `.error`. Cancelling the calling `Task` cancels the request (`.error(.cancelled)`).
    /// - Returns: `.success` with the decoded model, or `.error` with the reason it failed.
    func request() async -> HResponseWithResult<Model>
}

/// Default implementation for `HRequestWithResultProtocol`.
public extension HRequestWithResultProtocol {
    /// Default implementation that routes through `HRequestManager`.
    func request() async -> HResponseWithResult<Model> {
        return await HRequestManager.request(model: Model.self, request: self)
    }

    /// Default implementation using `JSONDecoder`.
    /// - Parameters:
    ///   - data: The raw data received from the response.
    ///   - model: The model type to decode.
    /// - Returns: The decoded model instance.
    /// - Throws: Decoding error if data cannot be parsed.
    func parseData<T: Codable>(data: Data, model: T.Type) throws -> T {
        let decoder = HConfig.jsonDecoder
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Request with Body Protocol
/// Protocol for requests that include a body (POST, PUT, PATCH).
///
/// The body is built from the first non-nil of `rawBody`, `multipartBody` and
/// `bodyParameters`, in that order. A request with none of them is sent without a body.
public protocol HRequestWithBodyProtocol: HRequestWithEmptyResponseProtocol {
    /// Parameters sent as a JSON object (`Content-Type: application/json`). Values must be
    /// representable in JSON (strings, numbers, booleans, `NSNull`, arrays and dictionaries of
    /// them); otherwise the request fails with `.malformedRequest(reason:)`.
    ///
    /// A get-only requirement: a computed property keeps a `Sendable` conformer free of
    /// `@unchecked Sendable`, which a stored `[String: Any]` would require.
    var bodyParameters: [String: Any]? { get }
    /// Multipart form values (`Content-Type: multipart/form-data`): text fields and files.
    /// When set, it is sent instead of `bodyParameters`. File parts are streamed from disk.
    /// Default: `nil`.
    var multipartBody: [String: HFormValue]? { get }
    /// Pre-encoded body sent as-is, instead of `multipartBody` and `bodyParameters`. It is sent
    /// with `Content-Type: application/json`; set a `Content-Type` in `headerParameters` to
    /// send another format. Default: `nil`.
    var rawBody: Data? { get }
}

// MARK: - HTTP Method Protocols
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
}
/// Protocol for POST requests that create new resources.
public protocol HPostRequestProtocol: HRequestWithBodyProtocol {}
/// Protocol for PATCH requests that partially update resources.
public protocol HPatchRequestProtocol: HRequestWithBodyProtocol {}
/// Protocol for PUT requests that update existing resources.
public protocol HPutRequestProtocol: HRequestWithBodyProtocol {}
/// Protocol for DELETE requests that remove resources.
public protocol HDeleteRequestProtocol: HRequestWithEmptyResponseProtocol {}

// MARK: - Default Implementations

/// Default implementations for `HGetRequestProtocol`.
public extension HGetRequestProtocol {
    /// The HTTP method for GET requests is `.get`.
    var httpMethod: HHttpMethod { .get }
    /// Default: `nil`.
    var queryParameters: [String: String]? { nil }
    /// Default: `nil`.
    var cacheType: HCache.CacheType? { nil }

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
            let remoteResult = await request()
            switch remoteResult {
            case .success(let data):
                continuation.yield((response: data, origin: .remote))
                continuation.finish()
            case .error(let error):
                continuation.finish(throwing: error)
            }

        case .cacheAndRemote:
            if let cachedData = await cache() {
                continuation.yield((response: cachedData, origin: .cache))
            }

            let remoteResult = await request()
            switch remoteResult {
            case .success(let data):
                continuation.yield((response: data, origin: .remote))
                continuation.finish()
            case .error(let error):
                continuation.finish(throwing: error)
            }
        }
    }
}

/// Default implementations for `HRequestWithBodyProtocol`.
public extension HRequestWithBodyProtocol {
    /// Default: `nil`.
    var multipartBody: [String: HFormValue]? { nil }
    /// Default: `nil`.
    var rawBody: Data? { nil }
}

/// Default implementations for `HPostRequestProtocol`.
public extension HPostRequestProtocol {
    /// The HTTP method for POST requests is `.post`.
    var httpMethod: HHttpMethod { .post }
}

/// Default implementations for `HPatchRequestProtocol`.
public extension HPatchRequestProtocol {
    /// The HTTP method for PATCH requests is `.patch`.
    var httpMethod: HHttpMethod { .patch }
}

/// Default implementations for `HPutRequestProtocol`.
public extension HPutRequestProtocol {
    /// The HTTP method for PUT requests is `.put`.
    var httpMethod: HHttpMethod { .put }
}

/// Default implementations for `HDeleteRequestProtocol`.
public extension HDeleteRequestProtocol {
    /// The HTTP method for DELETE requests is `.delete`.
    var httpMethod: HHttpMethod { .delete }
}
