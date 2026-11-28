//
//  HImageResponse.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// The outcome of loading an image. Loading never throws: a failure is a value.
public enum HImageResponse: Sendable {
    /// The image was loaded.
    case success(HImageResult)
    /// The image could not be loaded.
    case failure(HImageError)
}

// MARK: - Accessors

public extension HImageResponse {
    /// The loaded image, or `nil` on failure.
    var result: HImageResult? {
        if case .success(let result) = self { return result }
        return nil
    }

    /// The error, or `nil` on success.
    var error: HImageError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
