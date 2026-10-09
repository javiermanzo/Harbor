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
    var url: String
    var retryPolicy: HRetryPolicy?
    var pathParameters: [String: String]?
    var queryParameters: [String: String]?

    init(headerParameters: [String: String]? = nil, needsAuth: Bool = false, retryPolicy: HRetryPolicy? = nil, url: String, pathParameters: [String: String]? = nil, queryParameters: [String: String]? = nil) {
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.retryPolicy = retryPolicy
        self.url = url
        self.pathParameters = pathParameters
        self.queryParameters = queryParameters
    }
}

struct MockPostRequest: HPostRequestProtocol, @unchecked Sendable {
    var headerParameters: [String: String]?
    var needsAuth: Bool
    var pathParameters: [String: String]?
    var url: String = ""
    var bodyParameters: [String: Any]?


    init(headerParameters: [String: String]? = nil, needsAuth: Bool = false, pathParameters: [String: String]? = nil, url: String, bodyParameters: [String: Any]? = nil) {
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.pathParameters = pathParameters
        self.url = url
        self.bodyParameters = bodyParameters
    }
}

struct MockPostBodyRequest: HPostRequestProtocol, @unchecked Sendable {
    var headerParameters: [String: String]?
    var needsAuth: Bool
    var pathParameters: [String: String]?
    var url: String
    var bodyParameters: [String: Any]?
    var multipartBody: [String: HFormValue]?

    init(headerParameters: [String: String]? = nil, needsAuth: Bool = false, pathParameters: [String: String]? = nil, url: String, bodyParameters: [String: Any]? = nil, multipartBody: [String: HFormValue]? = nil) {
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.pathParameters = pathParameters
        self.url = url
        self.bodyParameters = bodyParameters
        self.multipartBody = multipartBody
    }
}

struct MockInvalidRequest: HRequestBaseRequestProtocol, @unchecked Sendable {
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

struct MockGetRequestWithRetries<T: HModel>: HGetRequestProtocol {
    typealias Model = T
    var headerParameters: [String: String]?
    var needsAuth: Bool
    var url: String
    var retryPolicy: HRetryPolicy?
    var pathParameters: [String: String]?
    var queryParameters: [String: String]?

    init(headerParameters: [String: String]? = nil, needsAuth: Bool = false, retryPolicy: HRetryPolicy? = nil, url: String, pathParameters: [String: String]? = nil, queryParameters: [String: String]? = nil) {
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.retryPolicy = retryPolicy
        self.url = url
        self.pathParameters = pathParameters
        self.queryParameters = queryParameters
    }
}

struct MockPutRequest<T: HModel>: HPutRequestProtocol, @unchecked Sendable {
    typealias Model = T
    var headerParameters: [String: String]?
    var needsAuth: Bool
    var url: String
    var pathParameters: [String: String]?
    var bodyParameters: [String: Any]?

    init(headerParameters: [String: String]? = nil, needsAuth: Bool = false, url: String, pathParameters: [String: String]? = nil, bodyParameters: [String: Any]? = nil) {
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.url = url
        self.pathParameters = pathParameters
        self.bodyParameters = bodyParameters
    }
}

struct MockPatchRequest<T: HModel>: HPatchRequestProtocol, @unchecked Sendable {
    typealias Model = T
    var headerParameters: [String: String]?
    var needsAuth: Bool
    var url: String
    var pathParameters: [String: String]?
    var bodyParameters: [String: Any]?

    init(headerParameters: [String: String]? = nil, needsAuth: Bool = false, url: String, pathParameters: [String: String]? = nil, bodyParameters: [String: Any]? = nil) {
        self.headerParameters = headerParameters
        self.needsAuth = needsAuth
        self.url = url
        self.pathParameters = pathParameters
        self.bodyParameters = bodyParameters
    }
}
