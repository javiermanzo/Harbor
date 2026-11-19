//
//  HRequestManagerActor.swift
//  HarborCore
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

/// Global actor to manage shared mutable state in a thread-safe way.
/// This actor ensures that Harbor's internal state is accessed safely across concurrent contexts.
@globalActor public actor HRequestManagerActor {
    /// The shared instance of the actor.
    public static let shared = HRequestManagerActor()
}

// MARK: - Isolated Reads

extension HRequestManagerActor {
    /// Runs `body` on `HRequestManagerActor` and returns its result, the equivalent of
    /// `MainActor.run`. Code outside the actor (e.g. another module's non-isolated helpers) uses
    /// it to read Harbor's configuration, whose types are isolated to the actor.
    /// - Parameter body: The closure to run on the actor.
    /// - Returns: The closure's result.
    package static func run<Result: Sendable>(_ body: @HRequestManagerActor @Sendable () -> Result) async -> Result {
        await body()
    }
}
