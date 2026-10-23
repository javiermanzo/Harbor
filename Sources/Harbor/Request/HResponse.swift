//
//  HResponse.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation
import HarborCore

/// The outcome of a request whose body is not decoded (`HRequestWithEmptyResponseProtocol`:
/// POST, PUT, PATCH and DELETE requests that do not also conform to `HRequestWithResultProtocol`).
public enum HResponse: Sendable {
    /// The request completed successfully.
    case success
    /// The request failed with an error.
    case error(HRequestError)
}
