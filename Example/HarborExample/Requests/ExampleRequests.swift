//
//  ExampleRequests.swift
//  HarborExample
//
//  Complete set of example requests demonstrating all Harbor features
//

import Foundation
import Harbor

// MARK: - GET Requests

/// Simple GET request - fetching all users
struct GetUsersRequest: HGetRequestProtocol {
    typealias Model = [User]
    let url: String = "\(JSONPlaceholderAPI.baseURL)/users"
}

/// GET with path parameter - fetching single user
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let userId: Int
    var url: String { "\(JSONPlaceholderAPI.baseURL)/users/\(userId)" }
}

/// GET with query parameters - search users
struct SearchUsersRequest: HGetRequestProtocol {
    typealias Model = [User]
    let url: String = "\(JSONPlaceholderAPI.baseURL)/users"

    let query: String

    var queryParameters: [String: String]? {
        ["q": query]
    }
}

/// GET with caching - user profile (changes infrequently)
struct GetUserProfileRequest: HGetRequestProtocol {
    typealias Model = User
    let userId: Int
    var url: String { "\(JSONPlaceholderAPI.baseURL)/users/\(userId)" }

    // Cache for 1 hour using custom cache
    var cacheType: HCache.CacheType? {
        .custom(HCache.Configuration(expirationTime: .oneHour))
    }
}

/// GET with URLCache (default with ETags)
struct GetPostsRequest: HGetRequestProtocol {
    typealias Model = [Post]
    let url: String = "\(JSONPlaceholderAPI.baseURL)/posts"

    // Uses URLCache with automatic ETag support (default)
    var cacheType: HCache.CacheType? {
        .urlCache()
    }
}

/// GET with pagination
struct GetPaginatedPostsRequest: HGetRequestProtocol {
    typealias Model = [Post]
    let url: String = "\(JSONPlaceholderAPI.baseURL)/posts"

    let page: Int
    let limit: Int

    var queryParameters: [String: String]? {
        ["_page": "\(page)", "_limit": "\(limit)"]
    }
}

/// GET posts for a specific user
struct GetUserPostsRequest: HGetRequestProtocol {
    typealias Model = [Post]
    let userId: Int
    var url: String { "\(JSONPlaceholderAPI.baseURL)/users/\(userId)/posts" }
}

// MARK: - POST Requests

/// Simple POST request - creating a new post (using class to avoid ambiguity)
final class CreatePostRequest: HPostRequestProtocol, @unchecked Sendable {
    typealias Model = Post
    let url: String = "\(JSONPlaceholderAPI.baseURL)/posts"

    let title: String
    let body: String
    let userId: Int

    var headerParameters: [String: String]?
    var needsAuth: Bool = false
    var retries: Int?
    var pathParameters: [String: String]?

    var bodyParameters: [String: Any]? {
        get {
            [
                "title": title,
                "body": body,
                "userId": userId
            ]
        }
        set { }
    }

    var bodyType: HRequestDataType { .json }

    init(title: String, body: String, userId: Int) {
        self.title = title
        self.body = body
        self.userId = userId
    }
}

/// POST with Codable model (using class)
final class CreatePostWithModelRequest: HPostRequestProtocol, @unchecked Sendable {
    typealias Model = Post
    let url: String = "\(JSONPlaceholderAPI.baseURL)/posts"

    let post: Post

    var headerParameters: [String: String]?
    var needsAuth: Bool = false
    var retries: Int?
    var pathParameters: [String: String]?

    var bodyParameters: [String: Any]? {
        get {
            guard let data = try? JSONEncoder().encode(post),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return dict
        }
        set { }
    }

    var bodyType: HRequestDataType { .json }

    init(post: Post) {
        self.post = post
    }
}

// MARK: - PUT Requests (Full Update)

/// PUT request - update entire post (using class)
final class UpdatePostRequest: HPutRequestProtocol, @unchecked Sendable {
    typealias Model = Post
    let postId: Int
    var url: String { "\(JSONPlaceholderAPI.baseURL)/posts/\(postId)" }

    let title: String
    let body: String
    let userId: Int

    var headerParameters: [String: String]?
    var needsAuth: Bool = false
    var retries: Int?
    var pathParameters: [String: String]?

    var bodyParameters: [String: Any]? {
        get {
            [
                "id": postId,
                "title": title,
                "body": body,
                "userId": userId
            ]
        }
        set { }
    }

    var bodyType: HRequestDataType { .json }

    init(postId: Int, title: String, body: String, userId: Int) {
        self.postId = postId
        self.title = title
        self.body = body
        self.userId = userId
    }
}

// MARK: - PATCH Requests (Partial Update)

/// PATCH request - update only specific fields (using class)
final class PatchPostRequest: HPatchRequestProtocol, @unchecked Sendable {
    typealias Model = Post
    let postId: Int
    var url: String { "\(JSONPlaceholderAPI.baseURL)/posts/\(postId)" }

    let title: String?

    var headerParameters: [String: String]?
    var needsAuth: Bool = false
    var retries: Int?
    var pathParameters: [String: String]?

    var bodyParameters: [String: Any]? {
        get {
            var params: [String: Any] = [:]
            if let title = title {
                params["title"] = title
            }
            return params.isEmpty ? nil : params
        }
        set { }
    }

    var bodyType: HRequestDataType { .json }

    init(postId: Int, title: String?) {
        self.postId = postId
        self.title = title
    }
}

// MARK: - DELETE Requests

/// DELETE request - delete a post
struct DeletePostRequest: HDeleteRequestProtocol, HRequestWithEmptyResponseProtocol {
    let postId: Int
    var url: String { "\(JSONPlaceholderAPI.baseURL)/posts/\(postId)" }
}

/// DELETE with response (using class)
final class DeletePostWithResponseRequest: HDeleteRequestProtocol, @unchecked Sendable {
    typealias Model = CreateResponse
    let postId: Int
    var url: String { "\(JSONPlaceholderAPI.baseURL)/posts/\(postId)" }

    var headerParameters: [String: String]?
    var needsAuth: Bool = false
    var retries: Int?
    var pathParameters: [String: String]?

    init(postId: Int) {
        self.postId = postId
    }
}

// MARK: - Requests with Authentication

/// Request requiring authentication
struct GetPrivateDataRequest: HGetRequestProtocol {
    typealias Model = User
    let url: String = "\(JSONPlaceholderAPI.baseURL)/users/1"
    let needsAuth: Bool = true
}

/// Response of the token-refresh demo stub server.
struct SecureDemoData: Codable, Sendable {
    let message: String
}

/// Request to the token-refresh demo stub server; requires auth and skips the cache
/// so every run exercises the full 401, refresh and retry flow.
struct GetSecureDemoDataRequest: HGetRequestProtocol {
    typealias Model = SecureDemoData
    let url: String = "https://\(AuthDemoStubProtocol.host)/secure-data"
    let needsAuth: Bool = true
    let cacheType: HCache.CacheType? = .disabled
}

/// Request with custom headers
struct GetDataWithHeadersRequest: HGetRequestProtocol {
    typealias Model = [User]
    let url: String = "\(JSONPlaceholderAPI.baseURL)/users"

    var headerParameters: [String: String]? {
        get {
            [
                "X-API-Version": "2.0",
                "X-Client-Platform": "iOS",
                "Accept-Language": "en-US"
            ]
        }
        set { }
    }
}

// MARK: - Requests with Retry

/// Request with retry configuration
struct GetUnreliableDataRequest: HGetRequestProtocol {
    typealias Model = [User]
    let url: String = "\(JSONPlaceholderAPI.baseURL)/users"

    // Retry up to 3 times on failure
    var retries: Int? {
        get { 3 }
        set { }
    }
}

// MARK: - Debug Requests

/// Request with debug enabled
struct DebugGetUsersRequest: HGetRequestProtocol, HDebugRequestProtocol {
    typealias Model = [User]
    let url: String = "\(JSONPlaceholderAPI.baseURL)/users"

    var debugType: HDebugRequestType = .requestAndResponse
}

// MARK: - Multipart Requests

/// Multipart POST request - upload with file (using class)
final class UploadPostRequest: HPostRequestProtocol, @unchecked Sendable {
    typealias Model = CreateResponse
    let url: String = "\(JSONPlaceholderAPI.baseURL)/posts"

    let title: String
    let body: String
    let userId: Int
    let imageData: Data?

    var headerParameters: [String: String]?
    var needsAuth: Bool = false
    var retries: Int?
    var pathParameters: [String: String]?

    var bodyParameters: [String: Any]? {
        get {
            var params: [String: Any] = [
                "title": title,
                "body": body,
                "userId": userId
            ]
            if let imageData = imageData {
                params["image"] = imageData
            }
            return params
        }
        set { }
    }

    var bodyType: HRequestDataType { .multipart }

    init(title: String, body: String, userId: Int, imageData: Data?) {
        self.title = title
        self.body = body
        self.userId = userId
        self.imageData = imageData
    }
}
