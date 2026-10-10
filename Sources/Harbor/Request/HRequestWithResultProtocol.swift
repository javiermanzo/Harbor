//
//  HRequestWithResultProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

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
