//
//  HURLBuilder.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import Foundation

/// Utility namespace for building composite URLs with path and query parameters. The
/// construction of whole requests (headers, bodies, multipart, cache validators) is in
/// `HURLBuilder+Request.swift`.
package enum HURLBuilder {
    /// Builds a composite URL from a base URL with optional path and query parameters.
    ///
    /// New query items are appended to the ones already present in the base URL and sorted
    /// by name, so the same input always produces the same URL; the composed URL can
    /// therefore be used as a deterministic cache key.
    /// - Parameters:
    ///   - url: The base URL string.
    ///   - pathParameters: Path parameters to substitute in the URL (e.g., {userId} -> 123).
    ///   - queryParameters: Query parameters to append to the URL.
    ///   - allowedSchemes: The lowercased schemes accepted. Default: `http` and `https`.
    /// - Returns: The composite URL.
    /// - Throws: `HRequestError.malformedRequest` when a path parameter contains a `..`
    ///   path segment, the resulting URL is invalid, or its scheme is not one of
    ///   `allowedSchemes` (compared case-insensitively; a URL without scheme is rejected too).
    package static func compositeURL(url: String, pathParameters: [String: String]? = nil, queryParameters: [String: String]? = nil, allowedSchemes: Set<String> = ["http", "https"]) throws -> URL {
        var compositeUrl = url

        if let pathParameters {
            for (key, value) in pathParameters {
                // Both "/" and "\" are treated as segment separators: some servers decode
                // %5C back into a path separator, so a backslash variant must not slip through.
                guard !value.split(whereSeparator: { $0 == "/" || $0 == "\\" }).contains("..") else {
                    throw HRequestError.malformedRequest(reason: "Path parameter \"\(key)\" contains a \"..\" path segment")
                }
                // "/" is encoded (%2F) so a value always stays within a single path segment.
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: pathParameterAllowed) ?? value
                compositeUrl = compositeUrl.replacingOccurrences(of: "{\(key)}", with: encodedValue)
            }
        }

        guard var urlComponents = URLComponents(string: compositeUrl) else {
            throw HRequestError.malformedRequest(reason: "Invalid URL")
        }

        if let queryParameters, !queryParameters.isEmpty {
            // Merge existing items (from the base URL, kept as written) with the new ones, then
            // sort the combined list by name. Sorting produces a canonical URL so semantically
            // equivalent requests share one cache key; ties keep their original order.
            // New names and values are strictly percent-encoded (only unreserved characters
            // stay literal): `+` would otherwise be decoded as a space by form decoders, and
            // `&`, `=`, `#` would split or truncate the item.
            var queryItems = urlComponents.percentEncodedQueryItems ?? []
            queryItems.append(contentsOf: queryParameters.map {
                URLQueryItem(name: percentEncodedQueryComponent($0.key), value: percentEncodedQueryComponent($0.value))
            })
            urlComponents.percentEncodedQueryItems = queryItems.enumerated()
                .sorted { ($0.element.name, $0.offset) < ($1.element.name, $1.offset) }
                .map(\.element)
        }

        guard let url = urlComponents.url else {
            throw HRequestError.malformedRequest(reason: "Invalid URL")
        }

        // Only the allowed schemes are sent: `URLSession` would also load `file://` and other
        // schemes. The reason names the scheme only, never the URL, which may carry credentials.
        let sortedSchemes = allowedSchemes.sorted()
        let supported = sortedSchemes.count > 1
            ? sortedSchemes.dropLast().joined(separator: ", ") + " and " + sortedSchemes[sortedSchemes.count - 1]
            : sortedSchemes.joined()
        guard let scheme = url.scheme?.lowercased() else {
            throw HRequestError.malformedRequest(reason: "URL has no scheme; only \(supported) are supported")
        }
        guard allowedSchemes.contains(scheme) else {
            throw HRequestError.malformedRequest(reason: "Unsupported URL scheme \"\(scheme)\"; only \(supported) are supported")
        }
        return url
    }

    /// Characters left literal in a path parameter value: `urlPathAllowed` without `/`, so a
    /// value cannot add path segments.
    private static let pathParameterAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()

    /// Characters left literal in a query item name or value: RFC 3986 unreserved characters.
    private static let queryComponentAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Percent-encodes a query item name or value, leaving only unreserved characters literal.
    /// - Parameter value: The raw name or value.
    private static func percentEncodedQueryComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryComponentAllowed) ?? value
    }
}
