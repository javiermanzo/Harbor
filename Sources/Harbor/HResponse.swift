//
//  HResponse.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

public enum HResponse {
    case success
    case cancelled
    case error(HRequestError)
}

public enum HResponseWithResult<Model: Sendable>: Sendable {
    case success(Model)
    case cancelled
    case error(HRequestError)
}
