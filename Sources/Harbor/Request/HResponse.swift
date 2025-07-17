//
//  HResponse.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

/// Response for requests that don't return data.
public enum HResponse: Sendable {
    /// The request completed successfully.
    case success
    /// The request failed with an error.
    case error(HRequestError)
}

/// Response for requests that return typed data models.
public enum HResponseWithResult<Model: Sendable>: Sendable {
    /// The request completed successfully with the parsed model.
    case success(Model)
    /// The request failed with an error.
    case error(HRequestError)
}
