//
//  HJRPCRequestManager.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

/// Internal manager responsible for performing single, notification, and batch JSON-RPC requests.
@HRequestManagerActor
enum HJRPCRequestManager: Sendable {
    /// Shared JSON-RPC configuration instance.
    static var config: HJRPCConfig = HJRPCConfig()
}

// MARK: - Single Request

extension HJRPCRequestManager {
    /// Performs a single JSON-RPC request for a given model type.
    /// - Parameters:
    ///   - model: The model type to decode from the response.
    ///   - request: The JSON-RPC request configuration.
    /// - Returns: An `HJRPCResponse<Model>` containing the result or error.
    static func request<Model: HModel>(model: Model.Type, request: any HJRPCRequestProtocol) async -> HJRPCResponse<Model> {
        let harborRequest: HJRPCRequestWrapper<Model>
        do {
            harborRequest = try request.wrapRequest(type: model)
        } catch {
            return .error(error)
        }

        let response: HResponseWithResult = await harborRequest.send()

        switch response {
        case .success(let envelope):
            guard let jsonrpc = envelope.jsonrpc, jsonrpc == config.jrpcVersion else {
                return .error(.invalidResponse)
            }

            if !request.isNotification,
               let envelopeID = envelope.id,
               envelopeID != .null,
               envelopeID != harborRequest.jrpcID {
                return .error(.idMismatch(expected: harborRequest.jrpcID, actual: envelopeID))
            }

            if let error = envelope.error {
                return .error(.jrpcError(error: error))
            }

            if let result = envelope.result {
                return .success(result)
            }

            if envelope.hasResult, envelope.resultIsNull {
                do {
                    let model = try JSONDecoder().decode(Model.self, from: Data("null".utf8))
                    return .success(model)
                } catch {
                    return .error(.invalidResponse)
                }
            }

            return .error(.invalidResponse)
        case .error(let harborError):
            return .error(error(from: harborError))
        }
    }
}

// MARK: - Notification

extension HJRPCRequestManager {
    /// Sends a JSON-RPC notification request (no response expected).
    ///
    /// The server MUST NOT reply to a notification (JSON-RPC 2.0, section 4.1), so a 2xx response
    /// with an empty (or whitespace-only) body counts as delivered. A 2xx body that is not a
    /// JSON-RPC response (e.g. an HTML page) throws `.codable`, and a JSON-RPC error object,
    /// in a 2xx or non-2xx response, throws `.jrpcError`.
    /// - Parameter request: The JSON-RPC request to notify.
    /// - Throws: An `HJRPCRequestError` if the request or URL is invalid or the notification delivery fails.
    static func notify(request: any HJRPCRequestProtocol) async throws {
        guard request.isNotification else {
            throw HJRPCRequestError.invalidRequest
        }

        let harborRequest: HJRPCRequestWrapper<HJSONValue> = try request.wrapRequest(type: HJSONValue.self)
        let response: HResponseWithResult = await harborRequest.send()

        switch response {
        case .success(let envelope):
            if let error = envelope.error {
                throw HJRPCRequestError.jrpcError(error: error)
            }
        case .error(let harborError):
            throw error(from: harborError)
        }
    }
}

// MARK: - Batch Request

extension HJRPCRequestManager {
    /// Executes a batch of JSON-RPC requests as a single HTTP payload.
    ///
    /// The requests are merged into one HTTP request as follows:
    /// - Endpoint: every request must resolve to the same endpoint (its `endpoint`, or the
    ///   configured URL); mixing endpoints throws `.malformedRequest`.
    /// - Headers: the `headerParameters` of every request are merged. When several requests set the same
    ///   header (compared case-insensitively), the value of the first request in the batch wins.
    /// - Authentication: the batch is authenticated when any request has `needsAuth`.
    /// - Retry: the first non-nil `retryPolicy` in the batch is used. Since a batch is a `POST`
    ///   that may contain writes, its `retryNonIdempotentRequests` is kept only when every request
    ///   in the batch declares a policy with `retryNonIdempotentRequests` set; otherwise the batch
    ///   is only retried after failures that happened before reaching the server.
    /// - Logging: the batch is logged when any request conforms to `HDebugRequestProtocol`, with
    ///   the most verbose debug type requested (request and response logging are combined).
    ///
    /// - Parameter requests: The list of JSON-RPC requests to include in the batch.
    /// - Returns: One `HJRPCBatchResponse` per response element returned by the server. An empty
    ///   `requests` array returns `[]` without a network call, as does a batch made only of
    ///   notifications answered with an empty body.
    /// - Throws: An `HJRPCRequestError` when the batch as a whole fails: no endpoint, encoding
    ///   failures, transport and HTTP errors, a body that is not a JSON-RPC batch response, or a
    ///   single JSON-RPC error object rejecting the whole batch (`.jrpcError`).
    static func batch(requests: [any HJRPCRequestProtocol]) async throws -> [HJRPCBatchResponse] {
        guard !requests.isEmpty else {
            return []
        }

        let url = try batchURL(for: requests)

        var elements: [[String: HJSONValue]] = []
        var requestIDs: [HJRPCId?] = []

        for request in requests {
            var element: [String: HJSONValue] = [
                "jsonrpc": .string(config.jrpcVersion),
                "method": .string(request.method),
            ]

            var effectiveID: HJRPCId?
            if !request.isNotification {
                let id = request.requestID ?? .generated()
                element["id"] = id.jsonValue
                effectiveID = id
            }

            if let parameters = try request.encodedParameters() {
                element["params"] = parameters
            }

            elements.append(element)
            requestIDs.append(effectiveID)
        }

        let rawBody: Data
        do {
            rawBody = try JSONEncoder().encode(elements)
        } catch {
            throw HJRPCRequestError.codable(modelName: "HJRPCBatch", error: error)
        }

        let harborRequest = HJRPCBatchWrapper(requestedDebugType: batchDebugType(for: requests),
                                              rawBody: rawBody,
                                              requestIDs: requestIDs,
                                              url: url,
                                              needsAuth: requests.contains { $0.needsAuth },
                                              retryPolicy: batchRetryPolicy(for: requests),
                                              headerParameters: batchHeaders(for: requests))
        let response: HResponseWithResult = await harborRequest.send()

        switch response {
        case .success(.empty):
            // Only a batch made exclusively of notifications may be answered with no body
            // (JSON-RPC 2.0, section 6).
            guard requestIDs.allSatisfy({ $0 == nil }) else {
                throw HJRPCRequestError.invalidResponse
            }
            return []
        case .success(.responses(let envelopes)):
            return envelopes.map { batchResponse(for: $0, httpStatusCode: nil) }
        case .success(.single(let envelope)):
            throw batchLevelError(for: envelope, httpStatusCode: nil)
        case .error(.api(let statusCode, let data)):
            // A non-2xx response may still carry JSON-RPC response objects.
            switch try? JSONDecoder().decode(HJRPCBatchPayload.self, from: data) {
            case .responses(let envelopes)?:
                return envelopes.map { batchResponse(for: $0, httpStatusCode: statusCode) }
            case .single(let envelope)? where envelope.error != nil:
                throw batchLevelError(for: envelope, httpStatusCode: statusCode)
            default:
                throw HJRPCRequestError.api(statusCode: statusCode, data: data)
            }
        case .error(let harborError):
            throw HJRPCRequestError.getError(hRequestError: harborError)
        }
    }

    /// The endpoint shared by every request in a batch.
    /// - Throws: `.urlNeeded` when no endpoint is configured, or `.malformedRequest` when the
    ///   requests target different endpoints.
    private static func batchURL(for requests: [any HJRPCRequestProtocol]) throws(HJRPCRequestError) -> String {
        let urls = Set(requests.map(\.resolvedURL))
        guard urls.count == 1, let url = urls.first else {
            throw .malformedRequest(reason: "All requests in a JSON-RPC batch must target the same endpoint.")
        }
        guard !url.isEmpty else {
            throw .urlNeeded
        }
        return url
    }

    /// The headers of every request merged; the first request that sets a header
    /// (compared case-insensitively) wins.
    static func batchHeaders(for requests: [any HJRPCRequestProtocol]) -> [String: String]? {
        var merged: [String: String] = [:]
        var seenNames: Set<String> = []
        for request in requests {
            guard let headers = request.headerParameters else { continue }
            for (name, value) in headers.sorted(by: { $0.key < $1.key }) where seenNames.insert(name.lowercased()).inserted {
                merged[name] = value
            }
        }
        return merged.isEmpty ? nil : merged
    }

    /// The first non-nil retry policy. Its `retryNonIdempotentRequests` is kept only when every
    /// request opts in, so a batch that contains a write is not re-sent after it may have
    /// reached the server.
    static func batchRetryPolicy(for requests: [any HJRPCRequestProtocol]) -> HRetryPolicy? {
        guard var policy = requests.lazy.compactMap(\.retryPolicy).first else {
            return nil
        }
        policy.retryNonIdempotentRequests = requests.allSatisfy { $0.retryPolicy?.retryNonIdempotentRequests == true }
        return policy
    }

    /// The most verbose debug type requested by the requests that opt into logging, or `nil`
    /// when none does. Request and response logging requested by different requests combine
    /// into `.requestAndResponse`.
    static func batchDebugType(for requests: [any HJRPCRequestProtocol]) -> HDebugRequestType? {
        let debugTypes = requests.compactMap(\.requestedDebugType)
        guard !debugTypes.isEmpty else {
            return nil
        }
        let logsRequest = debugTypes.contains { $0 == .request || $0 == .requestAndResponse }
        let logsResponse = debugTypes.contains { $0 == .response || $0 == .requestAndResponse }
        switch (logsRequest, logsResponse) {
        case (true, true):
            return .requestAndResponse
        case (true, false):
            return .request
        case (false, true):
            return .response
        case (false, false):
            return HDebugRequestType.none
        }
    }

    /// Maps one response object of a batch to an `HJRPCBatchResponse`.
    private static func batchResponse(for envelope: HJRPCResult<HJSONValue>, httpStatusCode: Int?) -> HJRPCBatchResponse {
        if var error = envelope.error {
            error.httpStatusCode = httpStatusCode
            return .error(id: envelope.id, error: .jrpcError(error: error))
        }

        if envelope.hasResult {
            return .success(id: envelope.id, result: envelope.result ?? .null)
        }

        return .error(id: envelope.id, error: .invalidResponse)
    }

    /// The error for a single response object returned for a whole batch.
    private static func batchLevelError(for envelope: HJRPCResult<HJSONValue>, httpStatusCode: Int?) -> HJRPCRequestError {
        guard var error = envelope.error else {
            return .invalidResponse
        }
        error.httpStatusCode = httpStatusCode
        return .jrpcError(error: error)
    }
}

// MARK: - Error Mapping

extension HJRPCRequestManager {
    /// Maps a Harbor error to an `HJRPCRequestError`. A non-2xx response whose body is a
    /// JSON-RPC error object surfaces as `.jrpcError`, with the HTTP status code in
    /// `HJRPCError.httpStatusCode`; any other failure maps through `HJRPCRequestError.getError`.
    /// - Parameter harborError: The error returned by Harbor.
    static func error(from harborError: HRequestError) -> HJRPCRequestError {
        if case .api(let statusCode, let data) = harborError,
           let envelope = try? JSONDecoder().decode(HJRPCResult<HJSONValue>.self, from: data),
           var error = envelope.error {
            error.httpStatusCode = statusCode
            return .jrpcError(error: error)
        }
        return HJRPCRequestError.getError(hRequestError: harborError)
    }
}
