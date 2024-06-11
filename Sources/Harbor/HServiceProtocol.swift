//
//  HServiceProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: -  Base Protocol
public protocol HServiceProtocolBase: AnyObject {
    var url: String { get set }
    var httpMethod: HHttpMethod { get set }
    var headerParameters: [String: String]? { get set }
    var queryParameters: [String: String]? { get set }
    var pathParameters: [String: String]? { get set }
    var body: [String: Any]? { get set }
    var needAuth: Bool { get }
    var timeout: TimeInterval { get set }
    func dataBody() -> Data?
}

extension HServiceProtocolBase {
    public func dataBody() -> Data? {
        do {
            if let body = self.body {
                let data = try JSONSerialization.data(withJSONObject: body as Any, options: .prettyPrinted)
                return data
            } else {
                return nil
            }
        } catch let error {
            print(error.localizedDescription)
            return nil
        }
    }
}

// MARK: -  Protocol With Result
public protocol HServiceProtocolWithResult: HServiceProtocolBase {
    associatedtype Model: Codable
    func parseData<T: Codable> (data: Data, model: T.Type) -> T?
    func request() async -> HResponseWithResult<Model>
}

public extension HServiceProtocolWithResult {
    func parseData<T: Codable> (data: Data, model: T.Type) -> T? {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch (let error) {
            return nil
        }
    }
    
    func request() async -> HResponseWithResult<Model> {
        return await HServiceManager.request(model: Model.self, service: self)
    }
}

// MARK: -  Protocol Without Result
public protocol HServiceProtocol: HServiceProtocolBase {
    func request(completion: @escaping (HResponse)->())
}

public extension HServiceProtocol {
    func request() async -> HResponse {
        return await HServiceManager.request(service: self)
    }
}
