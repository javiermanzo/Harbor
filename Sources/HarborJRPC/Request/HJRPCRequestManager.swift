//
//  HJRPCRequestManager.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor
import HarborCore

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
        guard !request.isNotification else {
            // A notification gets no response to decode: it is sent with `notify()`.
            return .error(.invalidRequest)
        }

        // Read before the network wait: the response is checked against the version the
        // request was sent with, even if `configure` changes it meanwhile.
        let expectedVersion = config.jrpcVersion
        let harborRequest: HJRPCRequestWrapper<Model>
        do {
            harborRequest = try request.wrapRequest(type: model)
        } catch {
            return .error(error)
        }

        let response: HResponseWithResult = await harborRequest.send()

        switch response {
        case .success(let envelope):
            guard let jsonrpc = envelope.jsonrpc, jsonrpc == expectedVersion else {
                return .error(.invalidResponse)
            }

            // A `null` id is what a server sends when it could not read the request's id
            // (e.g. a parse error), so it does not count as a mismatch.
            if let envelopeID = envelope.id,
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
    /// with an empty (or whitespace-only) body, or with a JSON object that is not an error
    /// object, counts as delivered. A 2xx body that is not a JSON object (e.g. an HTML page)
    /// throws `.codable`, and a JSON-RPC error object, in a 2xx or non-2xx response other than
    /// `401`, throws `.jrpcError`.
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
    /// - Timeout: the longest timeout of the requests (a request without `timeoutInterval` counts
    ///   with Harbor's default), or Harbor's default when none sets one.
    ///
    /// - Parameter requests: The list of JSON-RPC requests to include in the batch.
    /// - Returns: The responses in the order of `requests`: one element per request that is not a
    ///   notification (the i-th element answers the i-th such request, whatever order the server
    ///   used), followed by any element whose `id` matches no request (e.g. an error with a `null`
    ///   id). A request the server did not answer gets an `.error` with `.invalidResponse` and the
    ///   id it was sent with. An empty `requests` array returns `[]` without a network call, as
    ///   does a batch made only of notifications answered with an empty body. Like a single
    ///   request, every element of a 2xx response must carry the configured `jsonrpc` version: an
    ///   element that lacks it or differs, or that is not a valid response object, is an `.error`
    ///   with `.invalidResponse` (even when it holds an error object) and does not fail the other
    ///   elements. Elements of a non-2xx response are not version-checked, as for a single request.
    /// - Throws: An `HJRPCRequestError` when the batch as a whole fails: no endpoint, two requests
    ///   sharing an `id` (`.malformedRequest`), encoding failures, transport and HTTP errors, a
    ///   body that is not a JSON-RPC batch response, or a single JSON-RPC error object rejecting
    ///   the whole batch (`.jrpcError`, or `.invalidResponse` when a 2xx single object does not
    ///   carry the configured version).
    static func batch(requests: [any HJRPCRequestProtocol]) async throws -> [HJRPCBatchResponse] {
        guard !requests.isEmpty else {
            return []
        }

        let url = try batchURL(for: requests)
        // Read before the network wait, as for a single request.
        let expectedVersion = config.jrpcVersion

        var elements: [[String: HJSONValue]] = []
        var requestIDs: [HJRPCId?] = []

        for request in requests {
            var element: [String: HJSONValue] = [
                "jsonrpc": .string(expectedVersion),
                "method": .string(request.method),
            ]

            var effectiveID: HJRPCId?
            if !request.isNotification {
                let id = request.requestID ?? .generated()
                // Responses are matched to requests by id.
                guard !requestIDs.contains(id) else {
                    throw HJRPCRequestError.malformedRequest(reason: "Two requests in a JSON-RPC batch share the id \(id).")
                }
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
                                              url: url,
                                              needsAuth: requests.contains { $0.needsAuth },
                                              retryPolicy: batchRetryPolicy(for: requests),
                                              headerParameters: batchHeaders(for: requests),
                                              timeoutInterval: batchTimeout(for: requests),
                                              logName: "JSON-RPC batch (\(requests.count) requests)")
        let response: HResponseWithResult = await harborRequest.send()

        switch response {
        case .success(.empty):
            // Only a batch made exclusively of notifications may be answered with no body
            // (JSON-RPC 2.0, section 6).
            guard requestIDs.allSatisfy({ $0 == nil }) else {
                throw HJRPCRequestError.invalidResponse
            }
            return []
        case .success(.responses(let elements)):
            let responses = elements.map { batchResponse(for: $0, expectedVersion: expectedVersion, httpStatusCode: nil) }
            return orderedResponses(responses, requestIDs: requestIDs)
        case .success(.single(let envelope)):
            guard envelope.jsonrpc == expectedVersion else {
                throw HJRPCRequestError.invalidResponse
            }
            throw batchLevelError(for: envelope, httpStatusCode: nil)
        case .error(.api(let statusCode, let data)):
            // A non-2xx response may still carry JSON-RPC response objects.
            switch try? JSONDecoder().decode(HJRPCBatchPayload.self, from: data) {
            case .responses(let elements)?:
                let responses = elements.map { batchResponse(for: $0, expectedVersion: expectedVersion, httpStatusCode: statusCode) }
                return orderedResponses(responses, requestIDs: requestIDs)
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
    /// - Parameter requests: The requests of the batch.
    /// - Returns: The shared endpoint URL string.
    /// - Throws: `.urlNeeded` when no endpoint is configured, or `.malformedRequest` when the
    ///   requests target different endpoints.
    private static func batchURL(for requests: [any HJRPCRequestProtocol]) throws(HJRPCRequestError) -> String {
        let urls = Set(requests.map(\.resolvedURL))
        // A request without an endpoint when none is configured is reported as such, even if
        // other requests set their own `endpoint`.
        guard !urls.contains("") else {
            throw .urlNeeded
        }
        guard urls.count == 1, let url = urls.first else {
            throw .malformedRequest(reason: "All requests in a JSON-RPC batch must target the same endpoint.")
        }
        return url
    }

    /// The headers of every request merged; the first request that sets a header
    /// (compared case-insensitively) wins.
    /// - Parameter requests: The requests of the batch.
    /// - Returns: The merged headers, or `nil` when no request sets any.
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
    /// - Parameter requests: The requests of the batch.
    /// - Returns: The merged policy, or `nil` when no request has one.
    static func batchRetryPolicy(for requests: [any HJRPCRequestProtocol]) -> HRetryPolicy? {
        guard var policy = requests.lazy.compactMap(\.retryPolicy).first else {
            return nil
        }
        policy.retryNonIdempotentRequests = requests.allSatisfy { $0.retryPolicy?.retryNonIdempotentRequests == true }
        return policy
    }

    /// The longest timeout of the requests, counting those without one at Harbor's default, or
    /// `nil` (Harbor's default) when none sets one.
    /// - Parameter requests: The requests of the batch.
    static func batchTimeout(for requests: [any HJRPCRequestProtocol]) -> TimeInterval? {
        guard requests.contains(where: { $0.timeoutInterval != nil }) else { return nil }
        let defaultTimeout = HConfig.shared.timeoutInterval
        return requests.map { $0.timeoutInterval ?? defaultTimeout }.max()
    }

    /// The most verbose debug type requested by the requests that opt into logging, or `nil`
    /// when none does. Request and response logging requested by different requests combine
    /// into `.requestAndResponse`.
    /// - Parameter requests: The requests of the batch.
    /// - Returns: The combined debug type, or `nil` when no request logs.
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

    /// Maps one element of a batch response to an `HJRPCBatchResponse`.
    /// - Parameters:
    ///   - element: The response element.
    ///   - expectedVersion: The `jsonrpc` version the batch was sent with.
    ///   - httpStatusCode: The non-2xx HTTP status of the response carrying it, or `nil` for a 2xx.
    /// - Returns: `.error` for an error object, a malformed element, a response with neither
    ///   `result` nor `error`, or (2xx only, as for a single request) a response without the
    ///   expected `jsonrpc` version; `.success` otherwise.
    private static func batchResponse(for element: HJRPCBatchPayload.Element, expectedVersion: String, httpStatusCode: Int?) -> HJRPCBatchResponse {
        let envelope: HJRPCResult<HJSONValue>
        switch element {
        case .response(let response):
            envelope = response
        case .malformed(let id):
            return .error(id: id, error: .invalidResponse)
        }

        if httpStatusCode == nil, envelope.jsonrpc != expectedVersion {
            return .error(id: envelope.id, error: .invalidResponse)
        }

        if var error = envelope.error {
            error.httpStatusCode = httpStatusCode
            return .error(id: envelope.id, error: .jrpcError(error: error))
        }

        if envelope.hasResult {
            return .success(id: envelope.id, result: envelope.result ?? .null)
        }

        return .error(id: envelope.id, error: .invalidResponse)
    }

    /// Orders the responses like the requests that produced them: one element per request that
    /// is not a notification, in request order, then the responses whose `id` matches no request.
    /// A request without a response gets an `.error` with `.invalidResponse` and its own id.
    /// - Parameters:
    ///   - responses: The responses, in the order the server sent them.
    ///   - requestIDs: The ids the requests were sent with, in order (`nil` for notifications).
    /// - Returns: The ordered responses.
    static func orderedResponses(_ responses: [HJRPCBatchResponse], requestIDs: [HJRPCId?]) -> [HJRPCBatchResponse] {
        var unmatched = responses
        var ordered: [HJRPCBatchResponse] = []
        for id in requestIDs.compactMap({ $0 }) {
            if let index = unmatched.firstIndex(where: { $0.id == id }) {
                ordered.append(unmatched.remove(at: index))
            } else {
                ordered.append(.error(id: id, error: .invalidResponse))
            }
        }
        return ordered + unmatched
    }

    /// The error for a single response object returned for a whole batch.
    /// - Parameters:
    ///   - envelope: The response object.
    ///   - httpStatusCode: The non-2xx HTTP status of the response carrying it, or `nil` for a 2xx.
    /// - Returns: `.jrpcError` when the object carries an error, `.invalidResponse` otherwise.
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
    /// A `401` never gets here with its body: Harbor's auth flow reports it as `.authNeeded`.
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
