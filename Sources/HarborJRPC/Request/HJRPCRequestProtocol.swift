//
//  HJRPCRequestProtocol.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

// MARK: - HJRPCRequestProtocol

/// A typed JSON-RPC 2.0 call. Conform a `Sendable` struct to it, set `Model` and `method`, and
/// call `request()`.
///
/// Harbor builds the request object (`jsonrpc`, `method`, `params`, a generated `id`), sends it
/// as an HTTP `POST` through Harbor's pipeline (auth, retries, mocks, logging, pinning, mTLS)
/// and validates the response envelope (version, matching `id`, `result` or `error`).
///
/// ```swift
/// struct BalanceRequest: HJRPCRequestProtocol {
///     typealias Model = String
///     let address: String
///     let method = "eth_getBalance"
///     var parameters: HJRPCParams? { .positioned([address, "latest"]) }
/// }
///
/// let balance = try await BalanceRequest(address: "0x0").request()
/// ```
public protocol HJRPCRequestProtocol: Sendable {
    /// The model type that this request returns. Must conform to `HModel`.
    associatedtype Model: HModel

    /// The JSON-RPC method name to call.
    var method: String { get }

    /// Whether this request requires authentication. Default: `false`.
    var needsAuth: Bool { get }

    /// Optional retry policy (backoff and jitter) for failed requests. Default: `nil`.
    /// When `nil`, no retries are performed.
    ///
    /// The policy is applied exactly as written. JSON-RPC calls are sent as HTTP `POST`, which
    /// `HRetryPolicy` treats as non-idempotent: unless `retryNonIdempotentRequests` is `true`,
    /// only failures raised before the request reached the server (host not found, connection
    /// refused, no network) are retried. Read-only methods (e.g. `eth_call`, `eth_blockNumber`)
    /// that should also be retried after a retryable status code or a timeout must opt in:
    /// ```swift
    /// let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 3, retryNonIdempotentRequests: true)
    /// ```
    var retryPolicy: HRetryPolicy? { get }

    /// Additional HTTP headers to include in the request, on top of `Harbor`'s default headers.
    /// Default: `nil`.
    var headerParameters: [String: String]? { get }

    /// Parameters to send with the JSON-RPC request. Default: `nil`.
    var parameters: HJRPCParams? { get }

    /// Whether this request is a JSON-RPC notification. Notifications do not carry an `id`
    /// and the server does not respond to them: send them with `notify()` (or in a batch, where
    /// they produce no response element). Default: `false`.
    var isNotification: Bool { get }

    /// The identifier to send with the request. Default: `nil` (a UUID-based identifier is
    /// generated). Ignored for notifications.
    var requestID: HJRPCId? { get }

    /// The JSON-RPC endpoint this request is sent to. Default: `nil`, which uses the URL set with
    /// `HarborJRPC.configure(url:jrpcVersion:)`. Set it to call a
    /// different endpoint (e.g. another chain's RPC node) without changing the global configuration.
    var endpoint: URL? { get }

    /// Sends the request and returns the outcome as a value instead of throwing.
    /// - Returns: `.success` with the decoded `result`, or `.error` with the reason it failed.
    func requestResult() async -> HJRPCResponse<Model>

    /// Sends the request and returns the decoded `result`.
    /// - Returns: The decoded model on success.
    /// - Throws: An `HJRPCRequestError` when the request fails.
    func request() async throws -> Model

    /// Sends the JSON-RPC request as a notification. The request must have `isNotification` set to `true`.
    /// - Throws: `HJRPCRequestError.invalidRequest` if the request is not a notification, or another `HJRPCRequestError` when the request fails.
    func notify() async throws
}

// MARK: - Default Implementations

/// Default property implementations for `HJRPCRequestProtocol`.
public extension HJRPCRequestProtocol {
    /// Default: `false`, the request is sent without consulting the auth provider.
    var needsAuth: Bool { false }
    /// Default: `nil`, no retries are performed.
    var retryPolicy: HRetryPolicy? { nil }
    /// Default: `nil`, no additional HTTP headers.
    var headerParameters: [String: String]? { nil }
    /// Default: `nil`, the request carries no `params` member.
    var parameters: HJRPCParams? { nil }
    /// Default: `false`, the request carries an `id` and expects a response.
    var isNotification: Bool { false }
    /// Default: `nil`, a UUID-based identifier is generated per request.
    var requestID: HJRPCId? { nil }
    /// Default: `nil`, the globally configured JSON-RPC URL is used.
    var endpoint: URL? { nil }
}

/// Default request method implementations.
public extension HJRPCRequestProtocol {
    /// Sends the request through `HJRPCRequestManager` and validates the response envelope.
    func requestResult() async -> HJRPCResponse<Model> {
        return await HJRPCRequestManager.request(model: Model.self, request: self)
    }

    /// Executes the request and returns the decoded model, throwing on failure.
    func request() async throws -> Model {
        switch await requestResult() {
        case .success(let model):
            return model
        case .error(let error):
            throw error
        }
    }

    /// Sends the request as a JSON-RPC notification.
    func notify() async throws {
        guard isNotification else { throw HJRPCRequestError.invalidRequest }
        try await HJRPCRequestManager.notify(request: self)
    }
}

// MARK: - Internal Request Wrapping

/// Internal extension for wrapping JSON-RPC requests.
extension HJRPCRequestProtocol {
    /// The endpoint URL string this request is sent to: `endpoint`, or the configured URL.
    @HRequestManagerActor
    var resolvedURL: String {
        endpoint?.absoluteString ?? HJRPCRequestManager.config.url
    }

    /// The debug type of this request when it opts into logging by conforming to
    /// `HDebugRequestProtocol`, or `nil` when it does not.
    var requestedDebugType: HDebugRequestType? {
        (self as? HDebugRequestProtocol)?.debugType
    }

    /// The request's parameters encoded as an `HJSONValue`.
    /// - Throws: `HJRPCRequestError.codable` when a parameter cannot be encoded as JSON.
    func encodedParameters() throws(HJRPCRequestError) -> HJSONValue? {
        guard let parameters else { return nil }
        do {
            return try parameters.jsonValue()
        } catch {
            throw .codable(modelName: "HJRPCParams", error: error)
        }
    }

    /// Creates a Harbor-compatible request wrapper for this JSON-RPC request.
    /// - Parameter type: The raw response model type expected.
    /// - Returns: An `HJRPCRequestWrapper` instance encapsulating request metadata.
    /// - Throws: `HJRPCRequestError.urlNeeded` when no endpoint is configured, or
    ///   `HJRPCRequestError.codable` when the parameters cannot be encoded.
    @HRequestManagerActor
    func wrapRequest<RawModel: HModel>(type: RawModel.Type) throws(HJRPCRequestError) -> HJRPCRequestWrapper<RawModel> {
        let url = resolvedURL
        guard !url.isEmpty else {
            throw .urlNeeded
        }

        var jsonBody: [String: HJSONValue] = [
            "jsonrpc": .string(HJRPCRequestManager.config.jrpcVersion),
            "method": .string(method),
        ]

        var jrpcID: HJRPCId?
        if !isNotification {
            let effectiveID = requestID ?? .generated()
            jsonBody["id"] = effectiveID.jsonValue
            jrpcID = effectiveID
        }

        if let parameters = try encodedParameters() {
            jsonBody["params"] = parameters
        }

        let rawBody: Data
        do {
            rawBody = try JSONEncoder().encode(jsonBody)
        } catch {
            throw .codable(modelName: "HJRPCRequest", error: error)
        }

        return HJRPCRequestWrapper<RawModel>(requestedDebugType: requestedDebugType, jsonBody: jsonBody, rawBody: rawBody, jrpcID: jrpcID, url: url, needsAuth: needsAuth, retryPolicy: retryPolicy, headerParameters: headerParameters)
    }
}

// MARK: - Internal Transport Requests

/// Shape shared by the internal single and batch wrappers that carry JSON-RPC payloads
/// through Harbor.
protocol HJRPCTransportRequest: HPostRequestProtocol, HRequestWithResultProtocol {
    /// The debug type to log with, or `nil` when no wrapped request opted into logging
    /// by conforming to `HDebugRequestProtocol`.
    var requestedDebugType: HDebugRequestType? { get }
}

extension HJRPCTransportRequest {
    /// Sends the request through Harbor. Requests that opted into logging are sent through
    /// `HJRPCDebugRequest`, which conforms to `HDebugRequestProtocol`, so Harbor logs them
    /// with the requested debug type; the others are sent as-is and never logged, matching
    /// Harbor's opt-in logging for REST requests.
    func send() async -> HResponseWithResult<Model> {
        if let requestedDebugType {
            return await HJRPCDebugRequest(base: self, debugType: requestedDebugType).request()
        }
        return await request()
    }
}

/// Internal wrapper that adapts JSON-RPC requests to Harbor's request protocol.
struct HJRPCRequestWrapper<RawModel: HModel>: HJRPCTransportRequest {
    /// The JSON-RPC response envelope wrapping the request's model.
    typealias Model = HJRPCResult<RawModel>

    /// The debug type to log with, or `nil` when the request did not opt into logging.
    let requestedDebugType: HDebugRequestType?
    /// The request object (`jsonrpc`, `method`, `id`, `params`).
    let jsonBody: [String: HJSONValue]
    /// The encoded body that is sent. `JSONEncoder` keeps big integers (`HJSONValue.decimal`) exact.
    let rawBody: Data?
    /// The id sent with the request, or `nil` for a notification.
    let jrpcID: HJRPCId?
    /// The endpoint the request is sent to.
    let url: String
    /// Whether the request needs auth.
    let needsAuth: Bool
    /// The retry policy of the JSON-RPC request.
    let retryPolicy: HRetryPolicy?
    /// The headers of the JSON-RPC request.
    let headerParameters: [String: String]?

    /// The body as a dictionary, used by debug logs. The request itself is sent from `rawBody`.
    var bodyParameters: [String: Any]? {
        jsonBody.mapValues { $0.anyValue }
    }

    /// Decodes the response envelope. A notification answered with an empty (or whitespace-only)
    /// body decodes as an empty envelope, since the server MUST NOT reply to notifications
    /// (JSON-RPC 2.0, section 4.1); any other body must be a valid JSON-RPC response.
    func parseData<T: Codable>(data: Data, model: T.Type) throws -> T {
        if jrpcID == nil, data.isBlankJSONBody, let empty = HJRPCResult<RawModel>() as? T {
            return empty
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Internal wrapper that sends a JSON-RPC transport request with debug logging enabled.
struct HJRPCDebugRequest<Base: HJRPCTransportRequest>: HPostRequestProtocol, HRequestWithResultProtocol, HDebugRequestProtocol {
    /// The model of the wrapped request.
    typealias Model = Base.Model

    /// The wrapped transport request.
    let base: Base
    /// The debug type requested by the JSON-RPC request(s).
    let debugType: HDebugRequestType

    /// Forwarded from `base`.
    var url: String { base.url }
    /// Forwarded from `base`.
    var needsAuth: Bool { base.needsAuth }
    /// Forwarded from `base`.
    var retryPolicy: HRetryPolicy? { base.retryPolicy }
    /// Forwarded from `base`.
    var headerParameters: [String: String]? { base.headerParameters }
    /// Forwarded from `base`.
    var bodyParameters: [String: Any]? { base.bodyParameters }
    /// Forwarded from `base`.
    var rawBody: Data? { base.rawBody }

    /// Forwarded from `base`.
    func parseData<T: Codable>(data: Data, model: T.Type) throws -> T {
        try base.parseData(data: data, model: model)
    }
}

// MARK: - Response Body Helpers

/// Body inspection helpers for JSON-RPC responses.
extension Data {
    /// Whether the body is empty or contains only JSON whitespace.
    var isBlankJSONBody: Bool {
        allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }
    }
}
