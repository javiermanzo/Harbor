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

// MARK: - Request Data Type
/// Specifies the format of request body data.
public enum HRequestDataType: Sendable {
    /// JSON-encoded request body.
    case json
    /// Multipart form data request body.
    case multipart
}

// MARK: - Request Source
/// Specifies the data source preference for requests.
public enum HRequestSource: Sendable {
    /// Only fetch from remote server, ignore cache.
    case remoteOnly
    /// Only fetch from cache, don't make network request.
    case cacheOnly
    /// First try cache, then remote if cache miss.
    case cacheAndRemote
}

// MARK: - Origin Type
/// Indicates the origin of the response data.
public enum HOriginType: Sendable {
    /// Data came from local cache.
    case cache
    /// Data came from remote server.
    case remote
}

// MARK: - Base Protocol
/// Base protocol for all network requests. Defines fundamental properties.
public protocol HRequestBaseRequestProtocol: Sendable {
    /// The URL endpoint for the request.
    var url: String { get }
    /// The HTTP method to use for the request.
    var httpMethod: HHttpMethod { get }
    /// Whether this request requires authentication. Default: `false`.
    var needsAuth: Bool { get }
    /// Optional number of retry attempts for failed requests. Default: `nil`.
    /// Ignored when `retryPolicy` is set.
    ///
    /// - Warning: When both `retries` and `retryPolicy` are set, `retryPolicy` takes
    ///   precedence and `retries` is silently ignored. Prefer `retryPolicy` for new code;
    ///   this property may be removed in a future major release.
    var retries: Int? { get set }
    /// Optional retry policy (backoff and jitter) for failed requests. Default: `nil`
    /// (derived from `retries` and the configured default policy).
    var retryPolicy: HRetryPolicy? { get }
    /// Path parameters to be substituted in the URL. Default: `nil`.
    var pathParameters: [String: String]? { get }
    /// Additional HTTP headers to include in the request. Default: `nil`.
    var headerParameters: [String: String]? { get set }
    /// Timeout interval for this request. Default: `nil` (uses global config).
    var timeoutInterval: TimeInterval? { get }
}

/// Default implementations for `HRequestBaseRequestProtocol`.
public extension HRequestBaseRequestProtocol {
    /// Default: `false`.
    var needsAuth: Bool { false }
    /// Default: `nil`.
    var retries: Int? { get { nil } set { } }
    /// Default: `nil`.
    var retryPolicy: HRetryPolicy? { nil }
    /// Default: `nil`.
    var pathParameters: [String: String]? { nil }
    /// Default: `nil`.
    var headerParameters: [String: String]? { get { nil } set { } }
    /// Default: `nil`.
    var timeoutInterval: TimeInterval? { nil }
}

// MARK: - Request with Empty Result Protocol
/// Protocol for requests that return only success/failure status.
public protocol HRequestWithEmptyResponseProtocol: HRequestBaseRequestProtocol {
    /// Executes the request and returns a simple success/error response.
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
/// Protocol for requests that return typed data models.
public protocol HRequestWithResultProtocol: HRequestBaseRequestProtocol {
    /// The model type that this request returns.
    associatedtype Model: HModel
    /// Parses response data into the specified model type.
    func parseData<Model: Codable> (data: Data, model: Model.Type) throws -> Model
    /// Executes the request and returns a typed response.
    func request() async -> HResponseWithResult<Model>
}

/// Default implementation for `HRequestWithResultProtocol`.
public extension HRequestWithResultProtocol {
    /// Default implementation that routes through `HRequestManager`.
    func request() async -> HResponseWithResult<Model> {
        return await HRequestManager.request(model: Model.self, request: self)
    }
    
    /// Default implementation using `JSONDecoder`.
    func parseData<Model: Codable> (data: Data, model: Model.Type) throws -> Model {
        let decoder = JSONDecoder()
        return try decoder.decode(Model.self, from: data)
    }
}

// MARK: - Request with Body Protocol
/// Protocol for requests that include a body (POST, PUT, PATCH).
public protocol HRequestWithBodyProtocol: HRequestWithEmptyResponseProtocol {
    /// The format of the request body data. Default: `.json`.
    var bodyType: HRequestDataType { get }
    /// Parameters to include in the request body.
    var bodyParameters: [String: Any]? { get set }
    /// Typed multipart form values. When set, a multipart body is built from these values
    /// (text fields and files) instead of `bodyParameters`. Default: `nil`.
    var multipartBody: [String: HFormValue]? { get }
    /// Raw HTTP body data. When set, it is sent as-is instead of `bodyParameters` (Content-Type application/json).
    var rawBody: Data? { get }
}

// MARK: - HTTP Method Protocols
/// Protocol for GET requests that retrieve data.
public protocol HGetRequestProtocol: HRequestWithResultProtocol {
    /// Query parameters to append to the URL. Default: `nil`.
    var queryParameters: [String: String]? { get }
    /// Cache type for this request. Default: `nil` (uses global default).
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
    
    /// Creates an async throwing stream that emits responses from cache and/or remote sources.
    /// - Parameter source: The data source preference (default: .cacheAndRemote)
    /// - Returns: AsyncThrowingStream that yields (Model, HOriginType) tuples
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
    /// Default: `.json`.
    var bodyType: HRequestDataType { .json }
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
