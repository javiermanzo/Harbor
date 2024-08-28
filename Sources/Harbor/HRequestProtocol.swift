//
//  HRequestProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - Request Data Type
public enum HRequestDataType {
    case json
    case multipart
}

// MARK: - Base Protocol
public protocol HRequestBaseRequestProtocol {
    var url: String { get }
    var httpMethod: HHttpMethod { get }
    var needsAuth: Bool { get }
    var retries: Int? { get set }
    var pathParameters: [String: String]? { get }
    var headerParameters: [String: String]? { get set }
}

// MARK: - Request with Empty Result Protocol
public protocol HRequestWithEmptyResponseProtocol: HRequestBaseRequestProtocol {
    func request() async -> HResponse
}

public extension HRequestWithEmptyResponseProtocol {
    func request() async -> HResponse {
        return await HRequestManager.request(request: self)
    }
}

// MARK: - Request with Result Protocol
public protocol HRequestWithResultProtocol: HRequestBaseRequestProtocol {
    associatedtype Model: Codable
    func parseData<Model: Codable> (data: Data, model: Model.Type) throws -> Model
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
public protocol HRequestWithBodyProtocol: HRequestWithEmptyResponseProtocol {
    var bodyType: HRequestDataType { get set }
    var bodyParameters: [String: Any]? { get set }
}

// MARK: - Request types
public protocol HGetRequestProtocol: HRequestWithResultProtocol {
    var queryParameters: [String: String]? { get }
}
public protocol HPostRequestProtocol: HRequestWithBodyProtocol {}
public protocol HPatchRequestProtocol: HRequestWithBodyProtocol {}
public protocol HPutRequestProtocol: HRequestWithBodyProtocol {}
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
