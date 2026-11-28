//
//  View+HImagePrefetch.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import SwiftUI

// MARK: - Prefetch

public extension View {
    /// Prefetches images while the view is on screen, and stops when it leaves: put it on the
    /// last rows of a list to warm up the next page.
    /// - Parameters:
    ///   - requests: The images.
    ///   - destination: What prefetching warms up. Default: `.disk`.
    func hImagePrefetch(_ requests: [any HImageRequestProtocol], destination: HImagePrefetcher.Destination = .disk) -> some View {
        task(id: requests.map { $0.cacheKey ?? $0.url }) {
            await HImagePrefetcher(destination: destination).prefetch(requests)
        }
    }
}
