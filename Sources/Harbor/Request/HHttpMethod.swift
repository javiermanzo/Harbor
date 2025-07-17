//
//  HHttpMethod.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

/// HTTP methods supported by Harbor networking library.
public enum HHttpMethod: String {
    /// GET method for retrieving data.
    case get = "GET"
    /// POST method for creating new resources.
    case post = "POST"
    /// PUT method for updating existing resources.
    case put = "PUT"
    /// DELETE method for removing resources.
    case delete = "DELETE"
    /// PATCH method for partially updating resources.
    case patch = "PATCH"
}
