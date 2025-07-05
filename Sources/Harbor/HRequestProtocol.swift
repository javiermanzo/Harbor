//
//  HRequestProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - HModel
/// Type alias for models that can be used in network requests.
/// Must be both Codable for JSON serialization and Sendable for concurrency.
public typealias HModel = Codable & Sendable

// MARK: - Request Data Type
/// Specifies the format of request body data.
public enum HRequestDataType: Sendable {
    /// JSON-encoded request body.
    case json
    /// Multipart form data request body.
    case multipart
}

// MARK: - Base Protocol
/// Base protocol for all network requests.
/// Defines the fundamental properties that every request must have.
public protocol HRequestBaseRequestProtocol: Sendable {
    /// The URL endpoint for the request.
    var url: String { get }
    /// The HTTP method to use for the request.
    var httpMethod: HHttpMethod { get }
    /// Whether this request requires authentication.
    var needsAuth: Bool { get }
    /// Optional number of retry attempts for failed requests.
    var retries: Int? { get set }
    /// Path parameters to be substituted in the URL.
    var pathParameters: [String: String]? { get }
    /// Additional HTTP headers to include in the request.
    var headerParameters: [String: String]? { get set }
}

// MARK: - Request with Empty Result Protocol
/// Protocol for requests that don't return data, only success/failure status.
public protocol HRequestWithEmptyResponseProtocol: HRequestBaseRequestProtocol {
    /// Executes the request and returns a simple success/error response.
    /// - Returns: An `HResponse` indicating success or failure.
    func request() async -> HResponse
}

public extension HRequestWithEmptyResponseProtocol {
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
    /// - Parameters:
    ///   - data: The raw response data
    ///   - model: The model type to parse the data into
    /// - Returns: The parsed model instance
    /// - Throws: Decoding errors if parsing fails
    func parseData<Model: Codable> (data: Data, model: Model.Type) throws -> Model
    /// Executes the request and returns a typed response.
    /// - Returns: An `HResponseWithResult` containing either the parsed model or an error.
    func request() async -> HResponseWithResult<Model>
}

public extension HRequestWithResultProtocol {
    func request() async -> HResponseWithResult<Model> {
        return await HRequestManager.request(model: Model.self, request: self)
    }
    
    func parseData<Model: Codable> (data: Data, model: Model.Type) throws -> Model {
        let decoder = JSONDecoder()
        return try decoder.decode(Model.self, from: data)
    }
}

// MARK: - Request with Body Protocol
/// Protocol for requests that include a body (POST, PUT, PATCH).
public protocol HRequestWithBodyProtocol: HRequestWithEmptyResponseProtocol {
    /// The format of the request body data.
    var bodyType: HRequestDataType { get set }
    /// Parameters to include in the request body.
    var bodyParameters: [String: Any]? { get set }
}

// MARK: - Request types
/// Protocol for GET requests that retrieve data.
public protocol HGetRequestProtocol: HRequestWithResultProtocol {
    /// Query parameters to append to the URL.
    var queryParameters: [String: String]? { get }
}
/// Protocol for POST requests that create new resources.
public protocol HPostRequestProtocol: HRequestWithBodyProtocol {}
/// Protocol for PATCH requests that partially update resources.
public protocol HPatchRequestProtocol: HRequestWithBodyProtocol {}
/// Protocol for PUT requests that update existing resources.
public protocol HPutRequestProtocol: HRequestWithBodyProtocol {}
/// Protocol for DELETE requests that remove resources.
public protocol HDeleteRequestProtocol: HRequestWithEmptyResponseProtocol {}

public extension HGetRequestProtocol {
    var httpMethod: HHttpMethod { .get }
}

public extension HPostRequestProtocol {
    var httpMethod: HHttpMethod { .post }
}

public extension HPatchRequestProtocol {
    var httpMethod: HHttpMethod { .patch }
}

public extension HPutRequestProtocol {
    var httpMethod: HHttpMethod { .put }
}

public extension HDeleteRequestProtocol {
    var httpMethod: HHttpMethod { .delete }
}
