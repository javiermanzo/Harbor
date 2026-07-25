//
//  User.swift
//  HarborExample
//
//  Example models for Harbor networking
//

import Foundation

// MARK: - User Model
struct User: Codable, Sendable {
    let id: Int
    let name: String
    let email: String
    let username: String?
    let phone: String?
    let website: String?
    let address: Address?
    let company: Company?
}

struct Address: Codable, Sendable {
    let street: String
    let suite: String?
    let city: String
    let zipcode: String
    let geo: Geo?
}

struct Geo: Codable, Sendable {
    let lat: String
    let lng: String
}

struct Company: Codable, Sendable {
    let name: String
    let catchPhrase: String?
    let bs: String?
}

// MARK: - Post Model
struct Post: Codable, Sendable {
    let id: Int
    let userId: Int
    let title: String
    let body: String
}

// MARK: - Comment Model
struct Comment: Codable, Sendable {
    let id: Int
    let postId: Int
    let name: String
    let email: String
    let body: String
}

// MARK: - Todo Model
struct Todo: Codable, Sendable {
    let id: Int
    let userId: Int
    let title: String
    let completed: Bool
}

// MARK: - Album Model
struct Album: Codable, Sendable {
    let id: Int
    let userId: Int
    let title: String
}

// MARK: - Photo Model
struct Photo: Codable, Sendable {
    let id: Int
    let albumId: Int
    let title: String
    let url: String
    let thumbnailUrl: String
}

// MARK: - API Response Models
struct PaginatedResponse<T: Codable & Sendable>: Codable, Sendable {
    let data: [T]
    let page: Int
    let totalPages: Int
    let totalItems: Int
}

struct CreateResponse: Codable, Sendable {
    let id: Int
    let success: Bool
    let message: String?
}

struct ErrorResponse: Codable, Sendable {
    let error: String
    let code: Int
    let details: String?
}

// MARK: - Auth Models
struct LoginRequest: Codable, Sendable {
    let email: String
    let password: String
}

struct AuthToken: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - Form Data Model
struct FormData: Codable, Sendable {
    let title: String
    let body: String
    let userId: Int
}

// MARK: - JSONPlaceholder API Base
enum JSONPlaceholderAPI {
    static let baseURL = "https://jsonplaceholder.typicode.com"
}
