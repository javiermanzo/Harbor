//
//  HURLBuilder.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import Foundation

/// Utility class for building composite URLs with path and query parameters.
struct HURLBuilder {
    
    /// Builds a composite URL from a base URL with optional path and query parameters.
    /// - Parameters:
    ///   - url: The base URL string.
    ///   - pathParameters: Path parameters to substitute in the URL (e.g., {userId} -> 123).
    ///   - queryParameters: Query parameters to append to the URL.
    /// - Returns: The composite URL, or nil if the URL is malformed.
    static func compositeURL(url: String, pathParameters: [String: String]? = nil, queryParameters: [String: String]? = nil) -> URL? {
        var compositeUrl = url

        if let pathParameters {
            for (key, value) in pathParameters {
                compositeUrl = compositeUrl.replacingOccurrences(of: "{\(key)}", with: value)
            }
        }

        var url: URL? = URL(string: compositeUrl)

        if var urlComponents = URLComponents(string: compositeUrl), let queryParameters, !queryParameters.isEmpty {
            var queryItems = [URLQueryItem]()

            for (key, value) in queryParameters {
                queryItems.append(URLQueryItem(name: key, value: value))
            }

            queryItems.sort(by: { $0.name < $1.name })

            urlComponents.queryItems = queryItems
            url = urlComponents.url
        }

        return url
    }
}