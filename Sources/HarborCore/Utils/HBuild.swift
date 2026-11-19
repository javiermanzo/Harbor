//
//  HBuild.swift
//  HarborCore
//

/// Build-configuration facts about Harbor's own modules.
package enum HBuild {
    /// Whether HarborCore was compiled with the `DEBUG` condition (the products are built
    /// with the same configuration).
    package static let isDebug: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
}
