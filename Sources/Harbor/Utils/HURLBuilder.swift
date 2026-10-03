//
//  HURLBuilder.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import Foundation

/// Utility namespace for building composite URLs with path and query parameters.
enum HURLBuilder {
    /// A request ready to be sent.
    ///
    /// When `bodyFileURL` is set, the multipart body was streamed to that temporary file
    /// instead of being held in memory: send it with `URLSession.upload(for:fromFile:)` and
    /// call `removeBodyFile()` once the attempt is over (success, failure or cancellation).
    struct HPreparedRequest: Sendable {
        /// The request. Its `httpBody` is `nil` when `bodyFileURL` is set.
        var urlRequest: URLRequest
        /// Temporary file holding the request body, for multipart bodies with file parts.
        let bodyFileURL: URL?
        /// Whether Harbor injected `If-None-Match` / `If-Modified-Since` from its custom cache.
        /// Only then may a `304` without a cached body be answered by refetching without them;
        /// validators set by the caller belong to the caller.
        var injectedConditionalValidators = false

        /// Deletes the temporary body file, if any.
        func removeBodyFile() {
            guard let bodyFileURL else { return }
            try? FileManager.default.removeItem(at: bodyFileURL)
        }
    }

    /// Builds a complete URLRequest from a Harbor request protocol, with the whole body in
    /// memory (`httpBody`), including multipart file parts.
    ///
    /// For GET requests using the custom cache, the stored validators are injected as
    /// `If-None-Match` / `If-Modified-Since` so the server can answer `304 Not Modified`,
    /// unless the request already carries either conditional header.
    /// - Parameters:
    ///   - request: The request conforming to HRequestBaseRequestProtocol.
    ///   - authHeader: The authorization header fetched from the auth provider, applied on
    ///     top of the request's own headers. Injecting it here keeps the caller's request
    ///     object untouched, which matters when the conformer is a reference type.
    /// - Returns: A configured URLRequest.
    /// - Throws: `HRequestError.malformedRequest` when the URL or the body cannot be built.
    static func buildUrlRequest<P: HRequestBaseRequestProtocol>(request: P, authHeader: HAuthorizationHeader? = nil) async throws -> URLRequest {
        try await build(request: request, authHeader: authHeader, streamFileParts: false).urlRequest
    }

    /// Builds the request to send over the network. Identical to `buildUrlRequest` except that
    /// a multipart body containing file parts is streamed to a temporary file (file contents
    /// are copied in chunks, never loaded whole) and returned as `bodyFileURL`; text-only
    /// bodies stay in memory.
    /// - Parameters:
    ///   - request: The request conforming to HRequestBaseRequestProtocol.
    ///   - authHeader: The authorization header fetched from the auth provider.
    /// - Returns: The prepared request.
    /// - Throws: `HRequestError.malformedRequest` when the URL or the body cannot be built.
    static func prepareRequest<P: HRequestBaseRequestProtocol>(request: P, authHeader: HAuthorizationHeader? = nil) async throws -> HPreparedRequest {
        try await build(request: request, authHeader: authHeader, streamFileParts: true)
    }

    /// Shared implementation of `buildUrlRequest` and `prepareRequest`.
    /// - Parameters:
    ///   - request: The request conforming to HRequestBaseRequestProtocol.
    ///   - authHeader: The authorization header fetched from the auth provider.
    ///   - streamFileParts: Whether a multipart body with file parts is written to a temporary file.
    private static func build<P: HRequestBaseRequestProtocol>(request: P, authHeader: HAuthorizationHeader?, streamFileParts: Bool) async throws -> HPreparedRequest {
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
        var bodyFileURL: URL?
        var injectedConditionalValidators = false

        urlRequest.httpMethod = request.httpMethod.rawValue
        // Set per request so it holds for custom sessions and alternating timeouts never require a new session.
        let defaultTimeoutInterval = await HConfig.shared.timeoutInterval
        urlRequest.timeoutInterval = request.timeoutInterval ?? defaultTimeoutInterval
        urlRequest.httpShouldHandleCookies = await HConfig.shared.httpShouldHandleCookies

        if let request = request as? HRequestWithBodyProtocol {
            if let rawBody = request.rawBody {
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = rawBody
            } else if let multipartBody = request.multipartBody {
                let boundary = "Boundary-\(UUID().uuidString)"
                urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                if streamFileParts, Self.hasFileParts(multipartBody) {
                    bodyFileURL = try writeMultipartBody(fields: multipartBody, boundary: boundary)
                } else {
                    urlRequest.httpBody = try multipartDataBody(fields: multipartBody, boundary: boundary)
                }
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
            // Redact the provider's header in debug output even under a non-standard name.
            HRedactionPolicy.registerAuthHeaderKey(authHeader.key)
        }

        // Inject the stored validators as conditional headers for GET requests using the custom
        // cache. A conditional header set by the caller is kept as-is: the caller owns the
        // revalidation, so neither validator is injected.
        let hasCallerValidators = urlRequest.value(forHTTPHeaderField: "If-None-Match") != nil
            || urlRequest.value(forHTTPHeaderField: "If-Modified-Since") != nil
        if request.httpMethod == .get, !hasCallerValidators, let getRequest = request as? any HGetRequestProtocol {
            let cacheType: HCache.CacheType
            if let requestCacheType = getRequest.cacheType {
                cacheType = requestCacheType
            } else {
                cacheType = await HConfig.shared.cacheType
            }

            if case .custom = cacheType {
                // Same key as the cache reads and writes: credential-namespaced for requests that need auth.
                let cacheKey = HCache.Manager.cacheKey(for: url, authHeader: request.needsAuth ? authHeader : nil)
                let validators = await HCache.Manager.shared.getValidators(forKey: cacheKey, requestHeaders: urlRequest.allHTTPHeaderFields)
                if let etag = validators.etag {
                    urlRequest.setValue(etag, forHTTPHeaderField: "If-None-Match")
                    injectedConditionalValidators = true
                }
                if let lastModified = validators.lastModified {
                    urlRequest.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
                    injectedConditionalValidators = true
                }
            }
        }

        return HPreparedRequest(urlRequest: urlRequest, bodyFileURL: bodyFileURL, injectedConditionalValidators: injectedConditionalValidators)
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
            // `JSONSerialization` raises an uncatchable Objective-C exception for values JSON
            // cannot represent (Date, Data, NaN/infinite numbers, custom types): validate first.
            guard JSONSerialization.isValidJSONObject(params) else {
                let invalidKeys = params.keys.filter { !JSONSerialization.isValidJSONObject(["value": params[$0]!]) }.sorted()
                throw HRequestError.malformedRequest(reason: "Request body cannot be serialized as JSON: unsupported value for \(invalidKeys.map { "\"\($0)\"" }.joined(separator: ", "))")
            }
            do {
                return try JSONSerialization.data(withJSONObject: params)
            } catch {
                throw HRequestError.malformedRequest(reason: "Request body cannot be serialized as JSON: \(error.localizedDescription)")
            }
        }
    }

    /// Size of the chunks file parts are copied in.
    private static let fileChunkSize = 64 * 1024

    /// Whether the multipart fields contain at least one file part.
    static func hasFileParts(_ fields: [String: HFormValue]) -> Bool {
        fields.values.contains {
            if case .file = $0 { return true }
            return false
        }
    }

    /// Builds a multipart body from typed form values, in memory. Text fields are encoded as
    /// regular parts; file fields carry the file contents with a `filename` in the
    /// `Content-Disposition` and an optional `Content-Type`.
    /// - Parameters:
    ///   - fields: Dictionary of form fields.
    ///   - boundary: The multipart boundary string.
    /// - Returns: The encoded multipart body.
    /// - Throws: `HRequestError.malformedRequest` when a field is invalid or a file cannot be read.
    static func multipartDataBody(fields: [String: HFormValue], boundary: String) throws -> Data {
        var body = Data()
        try encodeMultipartBody(fields: fields, boundary: boundary) { body.append($0) }
        return body
    }

    /// Streams a multipart body to a new temporary file. File parts are copied in chunks, so
    /// memory use does not grow with the file sizes. The file is removed when encoding fails.
    /// - Parameters:
    ///   - fields: Dictionary of form fields.
    ///   - boundary: The multipart boundary string.
    /// - Returns: The URL of the temporary file; the caller owns it and must delete it.
    /// - Throws: `HRequestError.malformedRequest` when a field is invalid, a file cannot be
    ///   read, or the temporary file cannot be written.
    static func writeMultipartBody(fields: [String: HFormValue], boundary: String) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("harbor-multipart-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
            throw HRequestError.malformedRequest(reason: "Multipart body file cannot be created")
        }

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try encodeMultipartBody(fields: fields, boundary: boundary) { data in
                do {
                    try handle.write(contentsOf: data)
                } catch {
                    throw HRequestError.malformedRequest(reason: "Multipart body file cannot be written: \(error.localizedDescription)")
                }
            }
            return fileURL
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            if let hError = error as? HRequestError { throw hError }
            throw HRequestError.malformedRequest(reason: "Multipart body file cannot be written: \(error.localizedDescription)")
        }
    }

    /// Encodes a multipart body, handing it to `write` piece by piece. File parts are read
    /// in chunks of `fileChunkSize` bytes.
    /// - Parameters:
    ///   - fields: Dictionary of form fields.
    ///   - boundary: The multipart boundary string.
    ///   - write: Receives each encoded piece in order.
    /// - Throws: `HRequestError.malformedRequest` when a field is invalid or a file cannot be
    ///   read, or the error thrown by `write`.
    private static func encodeMultipartBody(fields: [String: HFormValue], boundary: String, write: (Data) throws -> Void) throws {
        for (name, field) in fields.sorted(by: { $0.key < $1.key }) {
            switch field {
            case .text(let value):
                try write(Data(try convertFormField(named: name, value: value, using: boundary).utf8))
            case .file(let url, let mimeType, let fileName):
                let resolvedFileName = fileName ?? url.lastPathComponent
                try validateFormFieldName(name)
                try validateFormFieldName(resolvedFileName)
                if let mimeType {
                    try validateHeaderComponent(mimeType, of: "mime type for field \"\(name)\"")
                }

                let fileHandle: FileHandle
                do {
                    fileHandle = try FileHandle(forReadingFrom: url)
                } catch {
                    throw HRequestError.malformedRequest(reason: "Multipart file for field \"\(name)\" cannot be read: \(error.localizedDescription)")
                }
                defer { try? fileHandle.close() }

                var part = "--\(boundary)\r\n"
                part += "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(resolvedFileName)\"\r\n"
                if let mimeType {
                    part += "Content-Type: \(mimeType)\r\n"
                }
                part += "\r\n"
                try write(Data(part.utf8))
                try copyFileContents(of: fileHandle, fieldName: name, boundary: boundary, write: write)
                try write(Data("\r\n".utf8))
            }
        }

        try write(Data("--\(boundary)--".utf8))
    }

    /// Copies a file part's contents in chunks, rejecting files that contain the boundary
    /// delimiter (it would corrupt the multipart framing on the receiver). The UUID-based
    /// boundary makes accidental collision essentially impossible; this is defense against a
    /// malicious or unlucky payload. The search window overlaps consecutive chunks so a
    /// delimiter split across chunks is still found.
    /// - Parameters:
    ///   - fileHandle: Handle reading the file.
    ///   - fieldName: The form field name, for error messages.
    ///   - boundary: The multipart boundary string.
    ///   - write: Receives each chunk.
    private static func copyFileContents(of fileHandle: FileHandle, fieldName: String, boundary: String, write: (Data) throws -> Void) throws {
        let boundaryDelimiter = Data("--\(boundary)".utf8)
        var carry = Data()
        while true {
            let chunk: Data
            do {
                guard let read = try fileHandle.read(upToCount: fileChunkSize), !read.isEmpty else { break }
                chunk = read
            } catch {
                throw HRequestError.malformedRequest(reason: "Multipart file for field \"\(fieldName)\" cannot be read: \(error.localizedDescription)")
            }

            let window = carry + chunk
            if window.range(of: boundaryDelimiter) != nil {
                throw HRequestError.malformedRequest(reason: "Multipart file for field \"\(fieldName)\" contains the boundary string")
            }
            carry = Data(window.suffix(boundaryDelimiter.count - 1))
            try write(chunk)
        }
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
                // "/" is encoded (%2F) so a value always stays within a single path segment.
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: pathParameterAllowed) ?? value
                compositeUrl = compositeUrl.replacingOccurrences(of: "{\(key)}", with: encodedValue)
            }
        }

        guard var urlComponents = URLComponents(string: compositeUrl) else {
            throw HRequestError.malformedRequest(reason: "Invalid URL \"\(compositeUrl)\"")
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
            throw HRequestError.malformedRequest(reason: "Invalid URL \"\(compositeUrl)\"")
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
    static func percentEncodedQueryComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryComponentAllowed) ?? value
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
