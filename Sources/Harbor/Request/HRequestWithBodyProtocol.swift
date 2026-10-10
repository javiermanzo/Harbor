//
//  HRequestWithBodyProtocol.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - Request with Body Protocol
/// Protocol for requests that include a body (POST, PUT, PATCH).
///
/// The body is built from the first non-nil of `rawBody`, `multipartBody` and
/// `bodyParameters`, in that order. A request with none of them is sent without a body.
public protocol HRequestWithBodyProtocol: HRequestWithEmptyResponseProtocol {
    /// Parameters sent as a JSON object (`Content-Type: application/json`). Values must be
    /// representable in JSON (strings, numbers, booleans, `NSNull`, arrays and dictionaries of
    /// them); otherwise the request fails with `.malformedRequest(reason:)`.
    ///
    /// A get-only requirement: a computed property keeps a `Sendable` conformer free of
    /// `@unchecked Sendable`, which a stored `[String: Any]` would require.
    var bodyParameters: [String: Any]? { get }
    /// Multipart form values (`Content-Type: multipart/form-data`): text fields and files.
    /// When set, it is sent instead of `bodyParameters`. File parts are streamed from disk.
    /// Harbor always sends its own `Content-Type: multipart/form-data; boundary=...`: a
    /// `Content-Type` in `headerParameters` or in the default headers is ignored for these requests.
    /// Default: `nil`.
    var multipartBody: [String: HFormValue]? { get }
    /// Pre-encoded body sent as-is, instead of `multipartBody` and `bodyParameters`. It is sent
    /// with `Content-Type: application/json`; set a `Content-Type` in `headerParameters` to
    /// send another format. Default: `nil`.
    var rawBody: Data? { get }
}

// MARK: - Default Implementations

/// Default implementations for `HRequestWithBodyProtocol`.
public extension HRequestWithBodyProtocol {
    /// Default: `nil`.
    var multipartBody: [String: HFormValue]? { nil }
    /// Default: `nil`.
    var rawBody: Data? { nil }
}
