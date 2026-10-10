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

/// GET with path parameter - fetching single user.
/// `{id}` is replaced by the percent-encoded value of `pathParameters`.
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let userId: Int
    let url: String = "\(JSONPlaceholderAPI.baseURL)/users/{id}"

    var pathParameters: [String: String]? {
        ["id": String(userId)]
    }
}

/// GET with query parameters - filter users by username (JSONPlaceholder filters on any field)
struct SearchUsersRequest: HGetRequestProtocol {
    typealias Model = [User]
    let url: String = "\(JSONPlaceholderAPI.baseURL)/users"

    let username: String

    var queryParameters: [String: String]? {
        ["username": username]
    }
}

/// GET with caching - user profile (changes infrequently)
struct GetUserProfileRequest: HGetRequestProtocol {
    typealias Model = User
    let userId: Int
    var url: String { "\(JSONPlaceholderAPI.baseURL)/users/\(userId)" }

    // Harbor's custom cache (memory + disk). It follows the response's Cache-Control/Expires;
    // `expirationTime` is the freshness used when the response carries no caching headers.
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

/// GET to the pinned host with the cache disabled, so every run performs a TLS handshake
/// that the SSL pin is checked against (a cached response would skip it).
struct GetPinnedUsersRequest: HGetRequestProtocol {
    typealias Model = [User]
    let url: String = "\(JSONPlaceholderAPI.baseURL)/users"
    let cacheType: HCache.CacheType? = .disabled
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

// MARK: - POST Requests

/// Simple POST request - creating a new post.
/// `bodyParameters` is a get-only requirement, so a computed property keeps the request a
/// plain `Sendable` struct. Adopting `HRequestWithResultProtocol` as well decodes the created
/// post from the response body (`let response: HResponseWithResult<Post> = await ...request()`).
struct CreatePostRequest: HPostRequestProtocol, HRequestWithResultProtocol {
    typealias Model = Post
    let url: String = "\(JSONPlaceholderAPI.baseURL)/posts"

    let title: String
    let body: String
    let userId: Int

    var bodyParameters: [String: Any]? {
        [
            "title": title,
            "body": body,
            "userId": userId
        ]
    }
}

/// POST with a Codable model encoded as the JSON body (`rawBody`), decoding the created post.
struct CreatePostWithModelRequest: HPostRequestProtocol, HRequestWithResultProtocol {
    typealias Model = Post
    let url: String = "\(JSONPlaceholderAPI.baseURL)/posts"

    let post: Post

    /// Sent as-is with `Content-Type: application/json`.
    var rawBody: Data? {
        try? JSONEncoder().encode(post)
    }

    var bodyParameters: [String: Any]? { nil }
}

// MARK: - PUT Requests (Full Update)

/// PUT request - update entire post, decoding the updated post from the response.
struct UpdatePostRequest: HPutRequestProtocol, HRequestWithResultProtocol {
    typealias Model = Post
    let postId: Int
    var url: String { "\(JSONPlaceholderAPI.baseURL)/posts/\(postId)" }

    let title: String
    let body: String
    let userId: Int

    var bodyParameters: [String: Any]? {
        [
            "id": postId,
            "title": title,
            "body": body,
            "userId": userId
        ]
    }
}

// MARK: - PATCH Requests (Partial Update)

/// PATCH request - update only specific fields, decoding the merged post from the response.
struct PatchPostRequest: HPatchRequestProtocol, HRequestWithResultProtocol {
    typealias Model = Post
    let postId: Int
    var url: String { "\(JSONPlaceholderAPI.baseURL)/posts/\(postId)" }

    let title: String?

    var bodyParameters: [String: Any]? {
        guard let title else { return nil }
        return ["title": title]
    }
}

// MARK: - DELETE Requests

/// DELETE request - delete a post
struct DeletePostRequest: HDeleteRequestProtocol {
    let postId: Int
    var url: String { "\(JSONPlaceholderAPI.baseURL)/posts/\(postId)" }
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

    let headerParameters: [String: String]? = [
        "X-API-Version": "2.0",
        "X-Client-Platform": "iOS",
        "Accept-Language": "en-US"
    ]
}

// MARK: - Requests with Retry

/// Request with retry configuration
struct GetUnreliableDataRequest: HGetRequestProtocol {
    typealias Model = [User]
    let url: String = "\(JSONPlaceholderAPI.baseURL)/users"

    // Retry up to 3 times on transient failures (408/425/429/500/502/503/504 and transient
    // network errors) with exponential backoff; `Retry-After` is honored on 429/503 up to 60 s.
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 3, baseDelay: 0.5)
}

// MARK: - Debug Requests

/// Request with debug enabled
struct DebugGetUsersRequest: HGetRequestProtocol, HDebugRequestProtocol {
    typealias Model = [User]
    let url: String = "\(JSONPlaceholderAPI.baseURL)/users"

    let debugType: HDebugRequestType = .requestAndResponse
}

// MARK: - Multipart Requests

/// Multipart POST request - text fields plus a file part.
/// `multipartBody` takes typed `HFormValue`s and takes precedence over `bodyParameters`;
/// file parts are streamed from disk.
struct UploadPostRequest: HPostRequestProtocol {
    let url: String = "\(JSONPlaceholderAPI.baseURL)/posts"

    let title: String
    let body: String
    let userId: Int
    let imageFileURL: URL?

    var bodyParameters: [String: Any]? { nil }

    var multipartBody: [String: HFormValue]? {
        var fields: [String: HFormValue] = [
            "title": .text(title),
            "body": .text(body),
            "userId": .text(String(userId))
        ]
        if let imageFileURL {
            fields["image"] = .file(url: imageFileURL, mimeType: "image/png", fileName: "image.png")
        }
        return fields
    }
}
