//
//  HJRPCRequestManager.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation
import Harbor

@HRequestManagerActor
enum HJRPCRequestManager {
    static var config: HJRPCConfig = HJRPCConfig()
}

// MARK: - Single Request

extension HJRPCRequestManager {
    static func request<Model: HModel>(model: Model.Type, request: any HJRPCRequestProtocol) async -> HJRPCResponse<Model> {
        guard !config.url.isEmpty else {
            return .error(.urlNeeded)
        }

        let harborRequest: HJRPCRequestWrapper<Model> = request.wrapRequest(type: model)
        let response: HResponseWithResult = await harborRequest.request()

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
            return .error(HJRPCRequestError.getError(hRequestError: harborError))
        }
    }
}

// MARK: - Notification

extension HJRPCRequestManager {
    static func notify(request: any HJRPCRequestProtocol) async throws {
        guard !config.url.isEmpty else {
            throw HJRPCRequestError.urlNeeded
        }

        guard request.isNotification else {
            throw HJRPCRequestError.invalidRequest
        }

        let harborRequest: HJRPCRequestWrapper<HJSONValue> = request.wrapRequest(type: HJSONValue.self)
        let response: HResponseWithResult = await harborRequest.request()

        switch response {
        case .success:
            return
        case .error(let harborError):
            // The server MUST NOT respond to a notification (JSON-RPC 2.0, section 4.1),
            // so a 2xx response whose body cannot be decoded as a JSON-RPC envelope
            // (for example an empty body) still counts as a delivered notification.
            if case .codable = harborError { return }
            throw HJRPCRequestError.getError(hRequestError: harborError)
        }
    }
}

// MARK: - Batch Request

extension HJRPCRequestManager {
    static func batch(requests: [any HJRPCRequestProtocol]) async -> [HJRPCBatchResponse] {
        guard !config.url.isEmpty else {
            return requests.map { .error(id: $0.requestID, error: .urlNeeded) }
        }

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

            if let parameters = request.parameters {
                element["params"] = parameters.jsonValue
            }

            elements.append(element)
            requestIDs.append(effectiveID)
        }

        let rawBody = (try? JSONEncoder().encode(elements)) ?? Data()

        let needsAuth = requests.contains { $0.needsAuth }

        let harborRequest = HJRPCBatchWrapper(debugType: .none, rawBody: rawBody, requestIDs: requestIDs, url: config.url, needsAuth: needsAuth, retries: nil, retryPolicy: nil, pathParameters: nil, headerParameters: nil)
        let response: HResponseWithResult = await harborRequest.request()

        switch response {
        case .success(let envelopes):
            return envelopes.map { envelope in
                if let error = envelope.error {
                    return .error(id: envelope.id, error: .jrpcError(error: error))
                }

                if envelope.hasResult {
                    return .success(id: envelope.id, result: envelope.result ?? .null)
                }

                return .error(id: envelope.id, error: .invalidResponse)
            }
        case .error(let harborError):
            // A batch containing only notifications produces no response at all
            // (JSON-RPC 2.0, sections 4.1 and 6), so an undecodable 2xx body
            // (for example an empty body) means there are no responses to report.
            if case .codable = harborError, requestIDs.allSatisfy({ $0 == nil }) {
                return []
            }
            let error = HJRPCRequestError.getError(hRequestError: harborError)
            return requestIDs.map { .error(id: $0, error: error) }
        }
    }
}
