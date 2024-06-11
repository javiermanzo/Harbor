//
//  HServiceProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - Request Data Type
public enum HServiceRequestDataType {
    case json
    case multipart
}

// MARK: - Base Protocol
public protocol HServiceBaseRequestProtocol: AnyObject {
    var url: String { get }
    var httpMethod: HHttpMethod { get }
    var needsAuth: Bool { get }
    var pathParameters: [String: String]? { get set }
    var headerParameters: [String: String]? { get set }
}

// MARK: - Request with Empty Result Protocol
public protocol HServiceEmptyResponseProtocol: HServiceBaseRequestProtocol {
    func request() async -> HResponse
}

public extension HServiceEmptyResponseProtocol {
    func request() async -> HResponse {
        return await HServiceManager.request(service: self)
    }
}

// MARK: - Request with Result Protocol
public protocol HServiceResultRequestProtocol: HServiceBaseRequestProtocol {
    associatedtype Model: Codable
    func parseData<Model: Codable> (data: Data, model: Model.Type) -> Model?
    func request() async -> HResponseWithResult<Model>
}

public extension HServiceResultRequestProtocol {
    func request() async -> HResponseWithResult<Model> {
        return await HServiceManager.request(model: Model.self, service: self)
    }

    func parseData<Model: Codable> (data: Data, model: Model.Type) -> Model? {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(Model.self, from: data)
        } catch {
            print("Error decoding model: \(model.self)")
            return nil
        }
    }
}

// MARK: - Request with Body Protocol
public protocol HServiceBodyRequestProtocol: HServiceEmptyResponseProtocol {
    var bodyType: HServiceRequestDataType { get set }
    var bodyParameters: [String: Any]? { get set }
}

// MARK: - Request types
public protocol HServiceGetRequestProtocol: HServiceResultRequestProtocol {
    var queryParameters: [String: String]? { get set }
}
public protocol HServicePostRequestProtocol: HServiceBodyRequestProtocol {}
public protocol HServicePatchRequestProtocol: HServiceBodyRequestProtocol {}
public protocol HServicePutRequestProtocol: HServiceBodyRequestProtocol {}
public protocol HServiceDeleteRequestProtocol: HServiceEmptyResponseProtocol {}

public extension HServiceGetRequestProtocol {
    var httpMethod: HHttpMethod { .get }
}

public extension HServicePostRequestProtocol {
    var httpMethod: HHttpMethod { .post }
}

public extension HServicePatchRequestProtocol {
    var httpMethod: HHttpMethod { .patch }
}

public extension HServicePutRequestProtocol {
    var httpMethod: HHttpMethod { .put }
}

public extension HServiceDeleteRequestProtocol {
    var httpMethod: HHttpMethod { .delete }
}
