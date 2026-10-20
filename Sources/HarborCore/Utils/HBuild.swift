//
//  HBuild.swift
//  Harbor
//

/// Build-configuration facts about the Harbor module itself.
package enum HBuild {
    /// Whether Harbor was compiled with the `DEBUG` condition.
    package static let isDebug: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
}
