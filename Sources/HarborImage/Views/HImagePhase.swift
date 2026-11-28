//
//  HImagePhase.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import SwiftUI

/// The state of an `HImageView`, handed to its content closure.
public enum HImagePhase {
    /// Loading; `progress` is the download progress in `0...1` when the server announces the
    /// size, `nil` otherwise.
    case empty(progress: Double?)
    /// The image. For an animated image it is the current frame, updated as it plays.
    case success(Image)
    /// The load failed.
    case failure(HImageError)
}

// MARK: - Accessors

public extension HImagePhase {
    /// The image, when the phase is `.success`.
    var image: Image? {
        if case .success(let image) = self { return image }
        return nil
    }

    /// The error, when the phase is `.failure`.
    var error: HImageError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

// MARK: - Identity

extension HImagePhase {
    /// Identifies the kind of phase, so a transition runs when the kind changes and not on every
    /// progress update or animation frame.
    var kind: Int {
        switch self {
        case .empty: return 0
        case .success: return 1
        case .failure: return 2
        }
    }

    /// Whether the phase is `.empty`.
    var isEmpty: Bool {
        kind == 0
    }
}
