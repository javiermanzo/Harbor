//
//  HResponse.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

public enum HResponse: Sendable {
    case success
    case error(HRequestError)
}

public enum HResponseWithResult<Model: Sendable>: Sendable {
    case success(Model)
    case error(HRequestError)
}
