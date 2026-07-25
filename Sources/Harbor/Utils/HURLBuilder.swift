//
//  HURLBuilder.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import Foundation

/// Utility class for building composite URLs with path and query parameters.
@HRequestManagerActor
struct HURLBuilder {
    /// Builds a complete URLRequest from a Harbor request protocol.
    /// - Parameter request: The request conforming to HRequestBaseRequestProtocol.
    /// - Returns: A configured URLRequest, or nil if the request cannot be built.
    static func buildUrlRequest<P: HRequestBaseRequestProtocol>(request: P) -> URLRequest? {
        let url: URL?

        switch request.httpMethod {
        case .get:
            guard let request = request as? (any HGetRequestProtocol) else { return nil }
            url = HURLBuilder.compositeURL(url: request.url, pathParameters: request.pathParameters, queryParameters: request.queryParameters)
        case .post, .put, .patch, .delete:
            url = HURLBuilder.compositeURL(url: request.url, pathParameters: request.pathParameters)
        }

        guard let url else { return nil }

        var urlRequest = URLRequest(url: url)

        urlRequest.httpMethod = request.httpMethod.rawValue
        // TODO: Move to a config class
        urlRequest.httpShouldHandleCookies = false

        if let request = request as? HRequestWithBodyProtocol, let parameters = request.bodyParameters {
            switch request.bodyType {
            case .json:
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = dataBody(params: parameters, type: .json, boundary: nil)
            case .multipart:
                let boundary = "Boundary-\(UUID().uuidString)"
                urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = dataBody(params: parameters, type: .multipart, boundary: boundary)
            }
        }

        if let defaultHeaderParameters = HConfig.shared.defaultHeaderParameters {
            urlRequest.allHTTPHeaderFields = mergeHeaderParameters(currentHeaders: urlRequest.allHTTPHeaderFields, newHeaders: defaultHeaderParameters)
        }

        if let requestHeaderParameters = request.headerParameters {
            urlRequest.allHTTPHeaderFields = mergeHeaderParameters(currentHeaders: urlRequest.allHTTPHeaderFields, newHeaders: requestHeaderParameters)
        }

        // --- Custom Cache ETag Injection ---
        // If this is a GET request using custom cache, inject If-None-Match if we have a stored ETag.
        // This is safe to do synchronously because HURLBuilder and HCache.Manager share @HRequestManagerActor.
        if let getRequest = request as? any HGetRequestProtocol {
            let cacheType = getRequest.cacheType ?? HConfig.shared.cacheType
            if case .custom = cacheType,
               let key = compositeURL(url: getRequest.url, pathParameters: getRequest.pathParameters, queryParameters: getRequest.queryParameters)?.absoluteString,
               let etag = HCache.Manager.shared.getETagSync(forKey: key) {
                urlRequest.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
        }

        return urlRequest
    }

    /// Creates request body data from parameters.
    /// - Parameters:
    ///   - params: Dictionary of parameters to include in the body.
    ///   - type: The data type (json or multipart).
    ///   - boundary: Optional boundary for multipart form data.
    /// - Returns: The encoded body data, or nil if encoding fails.
    static func dataBody(params: [String: Any], type: HRequestDataType, boundary: String? = nil) -> Data? {
        if type == .multipart, let boundary {
            return handleFormData(with: params, boundary: boundary)
        }

        do {
            return try JSONSerialization.data(withJSONObject: params, options: .prettyPrinted)
        } catch {
            return nil
        }
    }

    /// Handles multipart form data encoding.
    /// - Parameters:
    ///   - params: Dictionary of form fields.
    ///   - boundary: The multipart boundary string.
    /// - Returns: The encoded form data, or nil if encoding fails.
    static func handleFormData(with params: [String: Any], boundary: String) -> Data? {
        let httpBody = NSMutableData()
        for (key, value) in params {
            guard let value = value as? String else {
                return nil
            }

            httpBody.appendString(convertFormField(named: key, value: value, using: boundary))
        }

        httpBody.appendString("--\(boundary)--")
        return httpBody as Data
    }

    /// Converts a form field to its multipart representation.
    /// - Parameters:
    ///   - name: The field name.
    ///   - value: The field value.
    ///   - boundary: The multipart boundary string.
    /// - Returns: The formatted field string.
    static func convertFormField(named name: String, value: String, using boundary: String) -> String {
        var fieldString = "--\(boundary)\r\n"
        fieldString += "Content-Disposition: form-data; name=\"\(name)\"\r\n"
        fieldString += "\r\n"
        fieldString += "\(value)\r\n"
        return fieldString
    }

    /// Merges header parameters, with new values overriding existing ones.
    /// - Parameters:
    ///   - currentHeaders: Existing headers to merge into.
    ///   - newHeaders: New headers to apply.
    /// - Returns: The merged headers dictionary.
    static func mergeHeaderParameters(currentHeaders: [String: String]?, newHeaders: [String: String]) -> [String: String] {
        if let currentHeaders {
            var headers: [String: String] = currentHeaders

            if !newHeaders.isEmpty {
                headers.merge(newHeaders, uniquingKeysWith: { (_, new) in new })
            }
            return headers
        } else {
            return newHeaders
        }
    }

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
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
                compositeUrl = compositeUrl.replacingOccurrences(of: "{\(key)}", with: encodedValue)
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
