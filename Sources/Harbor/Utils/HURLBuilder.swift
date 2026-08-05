//
//  HURLBuilder.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import Foundation

/// Utility namespace for building composite URLs with path and query parameters.
enum HURLBuilder {
    /// Builds a complete URLRequest from a Harbor request protocol.
    ///
    /// For GET requests using the custom cache, the stored validators are injected as
    /// `If-None-Match` / `If-Modified-Since` so the server can answer `304 Not Modified`.
    /// - Parameters:
    ///   - request: The request conforming to HRequestBaseRequestProtocol.
    ///   - authHeader: The authorization header fetched from the auth provider, applied on
    ///     top of the request's own headers. Injecting it here keeps the caller's request
    ///     object untouched, which matters when the conformer is a reference type.
    /// - Returns: A configured URLRequest.
    /// - Throws: `HRequestError.malformedRequest` when the URL or the body cannot be built.
    static func buildUrlRequest<P: HRequestBaseRequestProtocol>(request: P, authHeader: HAuthorizationHeader? = nil) async throws -> URLRequest {
        let url: URL

        switch request.httpMethod {
        case .get:
            guard let getRequest = request as? (any HGetRequestProtocol) else {
                throw HRequestError.malformedRequest(reason: "GET request does not conform to HGetRequestProtocol")
            }
            url = try compositeURL(url: getRequest.url, pathParameters: getRequest.pathParameters, queryParameters: getRequest.queryParameters)
        case .post, .put, .patch, .delete:
            url = try compositeURL(url: request.url, pathParameters: request.pathParameters)
        }

        var urlRequest = URLRequest(url: url)

        urlRequest.httpMethod = request.httpMethod.rawValue
        urlRequest.httpShouldHandleCookies = await HConfig.shared.httpShouldHandleCookies

        if let request = request as? HRequestWithBodyProtocol {
            if let rawBody = request.rawBody {
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = rawBody
            } else if let multipartBody = request.multipartBody {
                let boundary = "Boundary-\(UUID().uuidString)"
                urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = try multipartDataBody(fields: multipartBody, boundary: boundary)
            } else if let parameters = request.bodyParameters {
                switch request.bodyType {
                case .json:
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = try dataBody(params: parameters, type: .json, boundary: nil)
                case .multipart:
                    let boundary = "Boundary-\(UUID().uuidString)"
                    urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = try dataBody(params: parameters, type: .multipart, boundary: boundary)
                }
            }
        }

        if let defaultHeaderParameters = await HConfig.shared.defaultHeaderParameters {
            urlRequest.allHTTPHeaderFields = mergeHeaderParameters(currentHeaders: urlRequest.allHTTPHeaderFields, newHeaders: defaultHeaderParameters)
        }

        if let requestHeaderParameters = request.headerParameters {
            urlRequest.allHTTPHeaderFields = mergeHeaderParameters(currentHeaders: urlRequest.allHTTPHeaderFields, newHeaders: requestHeaderParameters)
        }

        if let authHeader {
            urlRequest.setValue(authHeader.value, forHTTPHeaderField: authHeader.key)
        }

        // Inject the stored validators as conditional headers for GET requests using the custom cache.
        if request.httpMethod == .get, let getRequest = request as? any HGetRequestProtocol {
            let cacheType: HCache.CacheType
            if let requestCacheType = getRequest.cacheType {
                cacheType = requestCacheType
            } else {
                cacheType = await HConfig.shared.cacheType
            }

            if case .custom = cacheType {
                let validators = await HCache.Manager.shared.getValidators(forKey: url.absoluteString, requestHeaders: urlRequest.allHTTPHeaderFields)
                if let etag = validators.etag {
                    urlRequest.setValue(etag, forHTTPHeaderField: "If-None-Match")
                }
                if let lastModified = validators.lastModified {
                    urlRequest.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
                }
            }
        }

        return urlRequest
    }

    /// Creates request body data from parameters.
    /// - Parameters:
    ///   - params: Dictionary of parameters to include in the body.
    ///   - type: The data type (json or multipart).
    ///   - boundary: Optional boundary for multipart form data.
    /// - Returns: The encoded body data.
    /// - Throws: `HRequestError.malformedRequest` when the parameters cannot be encoded.
    static func dataBody(params: [String: Any], type: HRequestDataType, boundary: String? = nil) throws -> Data {
        switch type {
        case .multipart:
            guard let boundary else {
                throw HRequestError.malformedRequest(reason: "Multipart body requires a boundary")
            }
            return try handleFormData(with: params, boundary: boundary)
        case .json:
            do {
                return try JSONSerialization.data(withJSONObject: params)
            } catch {
                throw HRequestError.malformedRequest(reason: "Request body cannot be serialized as JSON: \(error.localizedDescription)")
            }
        }
    }

    /// Builds a multipart body from typed form values. Text fields are encoded as regular
    /// parts; file fields carry the file contents with a `filename` in the
    /// `Content-Disposition` and an optional `Content-Type`.
    /// - Parameters:
    ///   - fields: Dictionary of form fields.
    ///   - boundary: The multipart boundary string.
    /// - Returns: The encoded multipart body.
    /// - Throws: `HRequestError.malformedRequest` when a field is invalid or a file cannot be read.
    static func multipartDataBody(fields: [String: HFormValue], boundary: String) throws -> Data {
        var body = Data()
        for (name, field) in fields.sorted(by: { $0.key < $1.key }) {
            switch field {
            case .text(let value):
                body.append(Data(try convertFormField(named: name, value: value, using: boundary).utf8))
            case .file(let url, let mimeType, let fileName):
                let fileData: Data
                do {
                    fileData = try Data(contentsOf: url)
                } catch {
                    throw HRequestError.malformedRequest(reason: "Multipart file for field \"\(name)\" cannot be read: \(error.localizedDescription)")
                }

                // A file whose bytes contain the boundary delimiter would corrupt the multipart
                // framing on the receiver. The UUID-based boundary makes accidental collision
                // essentially impossible; this is defense against a malicious or unlucky payload.
                let boundaryDelimiter = Data("--\(boundary)".utf8)
                if fileData.range(of: boundaryDelimiter) != nil {
                    throw HRequestError.malformedRequest(reason: "Multipart file for field \"\(name)\" contains the boundary string")
                }

                let resolvedFileName = fileName ?? url.lastPathComponent
                try validateFormFieldName(name)
                try validateFormFieldName(resolvedFileName)
                if let mimeType {
                    try validateHeaderComponent(mimeType, of: "mime type for field \"\(name)\"")
                }

                var part = "--\(boundary)\r\n"
                part += "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(resolvedFileName)\"\r\n"
                if let mimeType {
                    part += "Content-Type: \(mimeType)\r\n"
                }
                part += "\r\n"
                body.append(Data(part.utf8))
                body.append(fileData)
                body.append(Data("\r\n".utf8))
            }
        }

        body.append(Data("--\(boundary)--".utf8))
        return body
    }

    /// Handles multipart form data encoding.
    /// - Parameters:
    ///   - params: Dictionary of form fields.
    ///   - boundary: The multipart boundary string.
    /// - Returns: The encoded form data.
    /// - Throws: `HRequestError.malformedRequest` when a field is invalid. A single invalid
    ///   field fails the whole body; a partial body is never produced.
    static func handleFormData(with params: [String: Any], boundary: String) throws -> Data {
        var body = Data()
        for (key, value) in params.sorted(by: { $0.key < $1.key }) {
            guard let value = formFieldValue(value) else {
                throw HRequestError.malformedRequest(reason: "Multipart value for field \"\(key)\" cannot be represented as a string")
            }
            body.append(Data(try convertFormField(named: key, value: value, using: boundary).utf8))
        }

        body.append(Data("--\(boundary)--".utf8))
        return body
    }

    /// Converts a form field to its multipart representation.
    /// - Parameters:
    ///   - name: The field name.
    ///   - value: The field value.
    ///   - boundary: The multipart boundary string.
    /// - Returns: The formatted field string.
    /// - Throws: `HRequestError.malformedRequest` when the name or value contains characters
    ///   that would break the multipart framing (CR/LF, a double quote in the name, or the
    ///   boundary string itself in the value).
    static func convertFormField(named name: String, value: String, using boundary: String) throws -> String {
        try validateFormFieldName(name)
        try validateHeaderComponent(value, of: "value for field \"\(name)\"")
        guard !value.contains(boundary) else {
            throw HRequestError.malformedRequest(reason: "Multipart value for field \"\(name)\" contains the boundary string")
        }

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
    ///
    /// New query items are appended to the ones already present in the base URL and sorted
    /// by name, so the same input always produces the same URL; the composed URL can
    /// therefore be used as a deterministic cache key.
    /// - Parameters:
    ///   - url: The base URL string.
    ///   - pathParameters: Path parameters to substitute in the URL (e.g., {userId} -> 123).
    ///   - queryParameters: Query parameters to append to the URL.
    /// - Returns: The composite URL.
    /// - Throws: `HRequestError.malformedRequest` when a path parameter contains a `..`
    ///   path segment or the resulting URL is invalid.
    static func compositeURL(url: String, pathParameters: [String: String]? = nil, queryParameters: [String: String]? = nil) throws -> URL {
        var compositeUrl = url

        if let pathParameters {
            for (key, value) in pathParameters {
                // Both "/" and "\" are treated as segment separators: some servers decode
                // %5C back into a path separator, so a backslash variant must not slip through.
                guard !value.split(whereSeparator: { $0 == "/" || $0 == "\\" }).contains("..") else {
                    throw HRequestError.malformedRequest(reason: "Path parameter \"\(key)\" contains a \"..\" path segment")
                }
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
                compositeUrl = compositeUrl.replacingOccurrences(of: "{\(key)}", with: encodedValue)
            }
        }

        guard var urlComponents = URLComponents(string: compositeUrl) else {
            throw HRequestError.malformedRequest(reason: "Invalid URL \"\(compositeUrl)\"")
        }

        if let queryParameters, !queryParameters.isEmpty {
            // Merge existing items (from the base URL) with the new ones, then sort the
            // combined list by name. Sorting produces a canonical URL so semantically
            // equivalent requests share one cache key.
            var queryItems = urlComponents.queryItems ?? []
            queryItems.append(contentsOf: queryParameters.map { URLQueryItem(name: $0.key, value: $0.value) })
            urlComponents.queryItems = queryItems.sorted { $0.name < $1.name }
        }

        guard let url = urlComponents.url else {
            throw HRequestError.malformedRequest(reason: "Invalid URL \"\(compositeUrl)\"")
        }
        return url
    }

    /// String representation of a form field value. Non-string scalars (numbers, booleans)
    /// are converted to their textual representation; any other type is rejected.
    private static func formFieldValue(_ value: Any) -> String? {
        switch value {
        case let value as String:
            return value
        case let bool as Bool:
            // Any NSNumber with a 0/1 value bridges to Bool, so a boolean is only
            // recognized through a genuine CFBoolean; numeric values keep their
            // numeric string form.
            if let number = value as? NSNumber {
                guard CFGetTypeID(number) == CFBooleanGetTypeID() else {
                    return number.stringValue
                }
            }
            return String(bool)
        case let value as any BinaryInteger:
            return String(describing: value)
        case let value as any BinaryFloatingPoint:
            return String(describing: value)
        default:
            return nil
        }
    }

    /// Validates a multipart field or file name: no CR/LF (header injection) and no double
    /// quote (it would terminate the quoted `name` in `Content-Disposition`).
    private static func validateFormFieldName(_ name: String) throws {
        try validateHeaderComponent(name, of: "field name")
        guard !name.contains("\"") else {
            throw HRequestError.malformedRequest(reason: "Multipart field name \"\(name)\" contains a double quote")
        }
    }

    /// Validates that a value embedded in a multipart header does not contain CR, LF, or NUL.
    /// CR/LF would let a malicious value start a new header (header injection); NUL is rejected
    /// as defense in depth because some intermediaries treat it as a terminator. Scalars are
    /// compared because a CRLF pair is a single `Character`.
    private static func validateHeaderComponent(_ value: String, of component: String) throws {
        let scalars = value.unicodeScalars
        guard !scalars.contains("\r"), !scalars.contains("\n"), !scalars.contains("\0") else {
            throw HRequestError.malformedRequest(reason: "Multipart \(component) contains an invalid character")
        }
    }
}
