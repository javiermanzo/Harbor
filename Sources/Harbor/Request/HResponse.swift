//
//  HResponse.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

/// The outcome of a request whose body is not decoded (POST, PUT, PATCH, DELETE).
public enum HResponse: Sendable {
    /// The request completed successfully.
    case success
    /// The request failed with an error.
    case error(HRequestError)
}

/// The outcome of a request decoded into `Model` (GET).
public enum HResponseWithResult<Model: Sendable>: Sendable {
    /// The request completed successfully with the parsed model.
    case success(Model)
    /// The request failed with an error.
    case error(HRequestError)
}
