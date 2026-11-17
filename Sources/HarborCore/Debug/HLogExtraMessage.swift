//
//  HLogExtraMessage.swift
//  HarborCore
//
//  Created by Javier Manzo on 16/11/2026.
//

import Foundation

/// A titled block of text attached to a log entry (for example a cURL command).
package struct HLogExtraMessage: Sendable {
    /// The block title.
    let key: String
    /// The block contents.
    let value: String

    /// Creates a block.
    /// - Parameters:
    ///   - key: The block title.
    ///   - value: The block contents.
    package init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}
