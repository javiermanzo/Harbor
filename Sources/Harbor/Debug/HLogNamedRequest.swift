//
//  HLogNamedRequest.swift
//  Harbor
//
//  Created by Javier Manzo on 23/10/2026.
//

import Foundation

/// A request that chooses the name its debug logs show. Wrapper requests of other products
/// (e.g. HarborJRPC's internal transport requests) adopt it so logs name the app's request
/// instead of the wrapper's generic type. Other requests are named after their type.
package protocol HLogNamedRequest {
    /// The name shown in debug logs.
    var logName: String { get }
}
