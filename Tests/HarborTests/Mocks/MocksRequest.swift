//
//  MocksRequest.swift
//
//
//  Created by Jalil on 18/06/24.
//

import Harbor

final class MockGetRequestService: HGetRequestProtocol {
    typealias Model = String
    var headerParameters: [String: String]?
    var needsAuth: Bool
    var url: String
    var pathParameters: [String: String]?
    var queryParameters: [String: String]?

    init(headerParameters: [String: String]? = nil, needsAuth: Bool = false, url: String, pathParameters: [String: String]? = nil, queryParameters: [String: String]? = nil) {
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.url = url
        self.pathParameters = pathParameters
        self.queryParameters = queryParameters
    }
}

final class MockPostRequestService: HPostRequestProtocol {
    var headerParameters: [String: String]?
    var needsAuth: Bool
    var pathParameters: [String: String]?
    var url: String = ""
    var bodyParameters: [String: Any]?
    var bodyType: HRequestDataType


    init(headerParameters: [String: String]? = nil, needsAuth: Bool = false, pathParameters: [String: String]? = nil, url: String, bodyParameters: [String: Any]? = nil, bodyType: HRequestDataType = .json) {
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.pathParameters = pathParameters
        self.url = url
        self.bodyParameters = bodyParameters
        self.bodyType = bodyType
    }
}

final class MockPostMultipartRequestService: HPostRequestProtocol {
    var headerParameters: [String: String]?
    var needsAuth: Bool
    var pathParameters: [String: String]?
    var url: String
    var bodyParameters: [String: Any]?
    var bodyType: HRequestDataType

    init(headerParameters: [String: String]? = nil, needsAuth: Bool = false, pathParameters: [String: String]? = nil, url: String, bodyParameters: [String: Any]? = nil, bodyType: HRequestDataType = .multipart) {
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.pathParameters = pathParameters
        self.url = url
        self.bodyParameters = bodyParameters
        self.bodyType = bodyType
    }
}

final class MockInvalidRequestService: HRequestBaseRequestProtocol {
    var headerParameters: [String: String]?
    var url: String
    var needsAuth: Bool = false
    var pathParameters: [String: String]?
    var httpMethod: HHttpMethod

    init(headerParameters: [String: String]? = nil, url: String = "", needsAuth: Bool = false, pathParameters: [String: String]? = nil, httpMethod: HHttpMethod = .get) {
        self.headerParameters = headerParameters
        self.url = url
        self.needsAuth = needsAuth
        self.pathParameters = pathParameters
        self.httpMethod = httpMethod
    }
}
