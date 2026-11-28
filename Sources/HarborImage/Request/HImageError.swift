//
//  HImageError.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// The reason an image could not be loaded, decoded, processed or encoded.
public enum HImageError: Sendable {
    /// The URL could not be built, its scheme is not `http`, `https`, `data` or `file`, a
    /// `file:` URL cannot be read, or a `data:` URL is malformed.
    case invalidURL(reason: String)
    /// The device is offline and no cached copy could be used (none on disk, or the cache
    /// policy is `.reloadIgnoringCache`).
    case noConnection
    /// The request has `needsAuth` set but no provider was configured with `Harbor.setAuthProvider(_:)`.
    case authProviderNeeded
    /// The server answered `401` and the credentials could not be refreshed through
    /// `HAuthProviderProtocol.authFailed()`, or the request does not set `needsAuth`.
    case authNeeded
    /// The server answered with a status code outside `200...299` (a `401` is `.authNeeded`).
    case api(statusCode: Int)
    /// The download timed out.
    case timeout
    /// The TLS handshake failed: SSL pinning rejected the server, its certificate chain is
    /// invalid, or the client certificate was missing or rejected.
    case certificate
    /// The download failed for a transport reason without a more specific case.
    case network(URLError)
    /// The image is not cached and the request used `.returnCacheDontLoad`.
    case notCached
    /// The operation was cancelled (the calling task, or the view leaving the screen).
    case cancelled
    /// The download is larger than `HarborImage.setMaxDownloadSizeInMBs(_:)`.
    case tooLarge(maxBytes: Int)
    /// The image has more pixels than `HarborImage.setMaxImagePixels(_:)` (a decompression bomb guard).
    case tooManyPixels(maxPixels: Int)
    /// The response is not an image (for example an HTML error page served with `200`).
    case notAnImage
    /// The image format, or a feature it uses (for example an SVG filter), is not supported, or
    /// an SVG has unsafe content (scripts, external references or entities).
    case unsupportedFormat(String)
    /// The image data is corrupted, truncated or malformed (a malformed SVG included), or a
    /// custom decoder threw an error that is not an `HImageError`.
    case decodingFailed
    /// A processor failed; the associated value describes why.
    case processingFailed(String)
    /// The image could not be encoded; the associated value describes why (for example a
    /// `maxBytes` that no quality satisfies).
    case encodingFailed(String)
}

// MARK: - Pipeline Errors

extension HImageError {
    /// Maps an error of Harbor's shared pipeline (URL building, auth, transport).
    /// - Parameter error: The pipeline error.
    init(pipelineError error: HRequestError) {
        switch error {
        case .api(let statusCode, _):
            self = .api(statusCode: statusCode)
        case .authProviderNeeded:
            self = .authProviderNeeded
        case .authNeeded:
            self = .authNeeded
        case .noConnection:
            self = .noConnection
        case .malformedRequest(let reason):
            self = .invalidURL(reason: reason ?? "Invalid URL")
        case .timeout:
            self = .timeout
        case .cancelled:
            self = .cancelled
        case .certificate:
            self = .certificate
        case .cannotFindHost:
            self = .network(URLError(.cannotFindHost))
        case .cannotConnectToHost:
            self = .network(URLError(.cannotConnectToHost))
        case .networkFailure(let urlError):
            self = .network(urlError)
        case .invalidHttpResponse:
            self = .network(URLError(.badServerResponse))
        case .noCachedDataFound:
            self = .notCached
        case .codable, .unknown:
            self = .decodingFailed
        }
    }

    /// Whether an expired copy on disk is served instead of this error: the server or the
    /// network failed transiently (transport error, timeout, `5xx`), so the copy is likely still
    /// right. A `4xx` means the image changed or is gone, and is reported.
    var allowsStaleCopy: Bool {
        switch self {
        case .network, .timeout:
            return true
        case .api(let statusCode):
            return (500...599).contains(statusCode)
        default:
            return false
        }
    }

    /// Whether another URL of `fallbackURLs` is worth trying after this error.
    var allowsFallback: Bool {
        switch self {
        case .api, .notAnImage, .unsupportedFormat, .decodingFailed, .tooLarge, .tooManyPixels, .invalidURL, .network, .timeout:
            return true
        case .noConnection, .authProviderNeeded, .authNeeded, .certificate, .notCached, .cancelled, .processingFailed, .encodingFailed:
            return false
        }
    }
}

// MARK: - Error

extension HImageError: Error {}

// MARK: - LocalizedError

extension HImageError: LocalizedError {
    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let reason):
            return "Invalid image URL: \(reason)"
        case .noConnection:
            return "No internet connection and the image is not cached"
        case .authProviderNeeded:
            return "The image request needs auth but no auth provider is configured"
        case .authNeeded:
            return "The server rejected the credentials"
        case .api(let statusCode):
            return "The server answered with status code \(statusCode)"
        case .timeout:
            return "The image download timed out"
        case .certificate:
            return "The TLS handshake failed"
        case .network(let urlError):
            return "The image download failed: \(urlError.localizedDescription)"
        case .notCached:
            return "The image is not cached"
        case .cancelled:
            return "The image load was cancelled"
        case .tooLarge(let maxBytes):
            return "The image is larger than \(maxBytes) bytes"
        case .tooManyPixels(let maxPixels):
            return "The image has more than \(maxPixels) pixels"
        case .notAnImage:
            return "The response is not an image"
        case .unsupportedFormat(let detail):
            return "Unsupported image format: \(detail)"
        case .decodingFailed:
            return "The image could not be decoded"
        case .processingFailed(let detail):
            return "The image could not be processed: \(detail)"
        case .encodingFailed(let detail):
            return "The image could not be encoded: \(detail)"
        }
    }
}

// MARK: - Equatable

extension HImageError: Equatable {}
