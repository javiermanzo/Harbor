//
//  AdvancedExampleRequests.swift
//  HarborExample
//
//  Advanced request patterns: pagination, cache-only, remote-only, etc.
//

import Foundation
import Harbor

// MARK: - Pagination Example

/// Paginated request using cursor-based pagination
struct CursorPaginatedUsersRequest: HGetRequestProtocol {
    typealias Model = CursorPaginatedResponse<User>

    let url: String = "\(JSONPlaceholderAPI.baseURL)/users"
    let cursor: String?
    let limit: Int

    var queryParameters: [String: String]? {
        get {
            var params: [String: String] = ["_limit": "\(limit)"]
            if let cursor = cursor {
                params["_cursor"] = cursor
            }
            return params
        }
        set { }
    }
}

struct CursorPaginatedResponse<T: Codable & Sendable>: Codable, Sendable {
    let data: [T]
    let nextCursor: String?
    let hasMore: Bool
}

// MARK: - Filtered Requests

/// Request with multiple filters
struct FilteredPostsRequest: HGetRequestProtocol {
    typealias Model = [Post]

    let url: String = "\(JSONPlaceholderAPI.baseURL)/posts"

    let userId: Int?
    let titleContains: String?

    var queryParameters: [String: String]? {
        get {
            var params: [String: String] = [:]

            if let userId = userId {
                params["userId"] = "\(userId)"
            }

            return params.isEmpty ? nil : params
        }
        set { }
    }
}

// MARK: - Error Handling Example

/// Request that returns error response
struct ErrorProneRequest: HGetRequestProtocol {
    typealias Model = ErrorResponse
    let url: String = "\(JSONPlaceholderAPI.baseURL)/posts/invalid"
}

// MARK: - Different Cache Strategies

/// Cache-only request - only use cached data, no network
struct CacheOnlyUsersRequest: HGetRequestProtocol {
    typealias Model = [User]
    let url: String = "\(JSONPlaceholderAPI.baseURL)/users"
}

/// Remote-only request - always fetch from network, ignore cache
struct RemoteOnlyUsersRequest: HGetRequestProtocol {
    typealias Model = [User]
    let url: String = "\(JSONPlaceholderAPI.baseURL)/users"

    var cacheType: HCache.CacheType? {
        get { .disabled }
        set { }
    }
}

// MARK: - Long-polling Example

/// Request designed for long-polling
struct LongPollRequest: HGetRequestProtocol {
    typealias Model = [Post]
    let url: String = "\(JSONPlaceholderAPI.baseURL)/posts"

    let sincePostId: Int?

    var queryParameters: [String: String]? {
        get {
            if let sincePostId = sincePostId {
                return ["id_gt": "\(sincePostId)"]
            }
            return nil
        }
        set { }
    }
}

// MARK: - Batch Request

/// Request for batch operations
struct BatchGetUsersRequest: HGetRequestProtocol {
    typealias Model = [User]
    let url: String = "\(JSONPlaceholderAPI.baseURL)/users"

    let userIds: [Int]

    var queryParameters: [String: String]? {
        get {
            let ids = userIds.map { String($0) }.joined(separator: ",")
            return ["id": ids]
        }
        set { }
    }
}

// MARK: - Conditional Request

/// Request with conditional headers
struct ConditionalGetRequest: HGetRequestProtocol {
    typealias Model = User
    let userId: Int
    var url: String { "\(JSONPlaceholderAPI.baseURL)/users/\(userId)" }

    let etag: String?

    var headerParameters: [String: String]? {
        get {
            var params: [String: String] = [:]
            if let etag = etag {
                params["If-None-Match"] = etag
            }
            return params.isEmpty ? nil : params
        }
        set { }
    }
}

// MARK: - Request with Custom Path Parameters

/// Request with path parameter replacement
struct GetUserPostRequest: HGetRequestProtocol {
    typealias Model = Post
    let userId: Int
    let postId: Int
    var url: String { "\(JSONPlaceholderAPI.baseURL)/users/\(userId)/posts/\(postId)" }
}

// MARK: - Form URL Encoded Request

/// POST with form URL encoded data
struct SubmitFormRequest: HPostRequestProtocol, HRequestWithResultProtocol {
    typealias Model = CreateResponse
    let url: String = "\(JSONPlaceholderAPI.baseURL)/posts"

    let name: String
    let email: String
    let message: String

    var bodyParameters: [String: Any]? {
        get {
            [
                "name": name,
                "email": email,
                "message": message
            ]
        }
        set { }
    }
}

// MARK: - Request Builder Pattern Example

/// Base request protocol with common configuration
protocol BaseAPIRequest: HGetRequestProtocol {
    var baseURL: String { get }
    var endpoint: String { get }
}

extension BaseAPIRequest {
    var baseURL: String { JSONPlaceholderAPI.baseURL }
    var url: String { "\(baseURL)/\(endpoint)" }
    var needsAuth: Bool { true }

    var headerParameters: [String: String]? {
        get {
            [
                "X-API-Version": "2.0",
                "X-Client-Version": "1.0.0"
            ]
        }
        set { }
    }
}

/// Usage of base request pattern
struct GetUsersFromAPI: BaseAPIRequest {
    typealias Model = [User]
    let endpoint = "users"
}
