//
//  HResponseWithResult.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import HarborCore

/// The outcome of a request decoded into `Model` (`HRequestWithResultProtocol`: GET requests,
/// and body requests that also conform to it).
public enum HResponseWithResult<Model: Sendable>: Sendable {
    /// The request completed successfully with the parsed model.
    case success(Model)
    /// The request failed with an error.
    case error(HRequestError)
}
