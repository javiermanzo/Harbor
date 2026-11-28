//
//  HImageDataResponse.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// The outcome of `HarborImage.data(for:onEvent:)`: the original bytes of an image, checked to
/// be an image but not decoded nor processed.
public enum HImageDataResponse: Sendable {
    /// The bytes were loaded.
    case success(data: Data, format: HImageFormat, source: HImageSource)
    /// The bytes could not be loaded.
    case failure(HImageError)
}

// MARK: - Accessors

public extension HImageDataResponse {
    /// The bytes, or `nil` on failure.
    var data: Data? {
        if case .success(let data, _, _) = self { return data }
        return nil
    }

    /// The error, or `nil` on success.
    var error: HImageError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
