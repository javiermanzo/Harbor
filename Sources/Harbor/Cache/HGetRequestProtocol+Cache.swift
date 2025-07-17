//
//  HGetRequestProtocol+Cache.swift
//  Harbor
//
//  Created by Javier Manzo on 08/07/2025.
//

import Foundation

public extension HGetRequestProtocol {

    /// Retrieves cached data for this request using the associated Model type.
    /// - Returns: The cached model if found and valid, `nil` otherwise.
    func cache() async -> Model? {
        return await HCache.Manager.shared.getCachedData(for: self)
    }

    /// Clears cached data for this specific request.
    func clearCache() async {
        guard let cacheKey else { return }
        await HCache.Manager.shared.removeCachedData(for: cacheKey)
    }
}

extension HGetRequestProtocol {
    /// Generates a cache key for this request based on the complete URL.
    var cacheKey: String? {
        let compositeURL: URL? = HURLBuilder.compositeURL(url: url,
                                                          pathParameters: pathParameters,
                                                          queryParameters: queryParameters)

        return compositeURL?.absoluteString
    }
}

