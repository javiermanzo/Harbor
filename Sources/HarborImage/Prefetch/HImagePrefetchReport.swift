//
//  HImagePrefetchReport.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// What a prefetch did.
public struct HImagePrefetchReport: Sendable, Equatable {
    /// Images loaded (or already cached).
    public private(set) var completed = 0
    /// Images that failed.
    public private(set) var failed = 0
    /// Images whose load was cancelled.
    public private(set) var cancelled = 0

    /// Creates an empty report.
    public init() {}
}

// MARK: - Recording

extension HImagePrefetchReport {
    /// Records the outcome of one image.
    /// - Parameter error: The error, or `nil` on success.
    mutating func record(_ error: HImageError?) {
        switch error {
        case .none: completed += 1
        case .some(.cancelled): cancelled += 1
        case .some: failed += 1
        }
    }
}
