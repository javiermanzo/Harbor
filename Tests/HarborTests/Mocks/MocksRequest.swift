//
//  MocksRequest.swift
//
//
//  Created by Jalil on 18/06/24.
//

import Harbor

struct MockGetRequest<T: HModel>: HGetRequestProtocol {

    typealias Model = T
    var headerParameters: [String: String]?
    var needsAuth: Bool
    var retries: Int?
    var url: String
    var pathParameters: [String: String]?
    var queryParameters: [String: String]?

    init(headerParameters: [String: String]? = nil, needsAuth: Bool = false, retries: Int? = nil, url: String, pathParameters: [String: String]? = nil, queryParameters: [String: String]? = nil) {
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.retries = retries
        self.url = url
        self.pathParameters = pathParameters
        self.queryParameters = queryParameters
    }
}

struct MockPostRequest: HPostRequestProtocol, @unchecked Sendable {
    var headerParameters: [String: String]?
    var needsAuth: Bool
    var retries: Int?
    var pathParameters: [String: String]?
    var url: String = ""
    var bodyParameters: [String: Any]?
    var bodyType: HRequestDataType


    init(headerParameters: [String: String]? = nil, needsAuth: Bool = false, retries: Int? = nil, pathParameters: [String: String]? = nil, url: String, bodyParameters: [String: Any]? = nil, bodyType: HRequestDataType = .json) {
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.retries = retries
        self.pathParameters = pathParameters
        self.url = url
        self.bodyParameters = bodyParameters
        self.bodyType = bodyType
    }
}

struct MockPostBodyRequest: HPostRequestProtocol, @unchecked Sendable {
    var headerParameters: [String: String]?
    var needsAuth: Bool
    var retries: Int?
    var pathParameters: [String: String]?
    var url: String
    var bodyParameters: [String: Any]?
    var bodyType: HRequestDataType
    var multipartBody: [String: HFormValue]?

    init(headerParameters: [String: String]? = nil, needsAuth: Bool = false, retries: Int? = nil, pathParameters: [String: String]? = nil, url: String, bodyParameters: [String: Any]? = nil, bodyType: HRequestDataType = .multipart, multipartBody: [String: HFormValue]? = nil) {
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.retries = retries
        self.pathParameters = pathParameters
        self.url = url
        self.bodyParameters = bodyParameters
        self.bodyType = bodyType
        self.multipartBody = multipartBody
    }
}

struct MockInvalidRequest: HRequestBaseRequestProtocol, @unchecked Sendable {
    var headerParameters: [String: String]?
    var url: String
    var needsAuth: Bool = false
    var retries: Int?
    var pathParameters: [String: String]?
    var httpMethod: HHttpMethod

    init(headerParameters: [String: String]? = nil, url: String = "", needsAuth: Bool = false, retries: Int? = nil, pathParameters: [String: String]? = nil, httpMethod: HHttpMethod = .get) {
        self.headerParameters = headerParameters
        self.url = url
        self.needsAuth = needsAuth
        self.retries = retries
        self.pathParameters = pathParameters
        self.httpMethod = httpMethod
    }
}

struct MockGetRequestWithRetries<T: HModel>: HGetRequestProtocol {
    typealias Model = T
    var headerParameters: [String: String]?
    var needsAuth: Bool
    var retries: Int?
    var url: String
    var pathParameters: [String: String]?
    var queryParameters: [String: String]?

    init(headerParameters: [String: String]? = nil, needsAuth: Bool = false, retries: Int? = nil, url: String, pathParameters: [String: String]? = nil, queryParameters: [String: String]? = nil) {
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.retries = retries
        self.url = url
        self.pathParameters = pathParameters
        self.queryParameters = queryParameters
    }
}

struct MockPutRequest<T: HModel>: HPutRequestProtocol, @unchecked Sendable {
    typealias Model = T
    var headerParameters: [String: String]?
    var needsAuth: Bool
    var retries: Int?
    var url: String
    var pathParameters: [String: String]?
    var bodyParameters: [String: Any]?
    var bodyType: HRequestDataType

    init(headerParameters: [String: String]? = nil, needsAuth: Bool = false, retries: Int? = nil, url: String, pathParameters: [String: String]? = nil, bodyParameters: [String: Any]? = nil, bodyType: HRequestDataType = .json) {
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.retries = retries
        self.url = url
        self.pathParameters = pathParameters
        self.bodyParameters = bodyParameters
        self.bodyType = bodyType
    }
}

struct MockPatchRequest<T: HModel>: HPatchRequestProtocol, @unchecked Sendable {
    typealias Model = T
    var headerParameters: [String: String]?
    var needsAuth: Bool
    var retries: Int?
    var url: String
    var pathParameters: [String: String]?
    var bodyParameters: [String: Any]?
    var bodyType: HRequestDataType

    init(headerParameters: [String: String]? = nil, needsAuth: Bool = false, retries: Int? = nil, url: String, pathParameters: [String: String]? = nil, bodyParameters: [String: Any]? = nil, bodyType: HRequestDataType = .json) {
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.retries = retries
        self.url = url
        self.pathParameters = pathParameters
        self.bodyParameters = bodyParameters
        self.bodyType = bodyType
    }
}
