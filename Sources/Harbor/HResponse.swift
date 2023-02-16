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
    case error(HServiceError)
}

public enum HResponseWithResult<T> {
    case success(T)
    case cancelled
    case error(HServiceError)
}

