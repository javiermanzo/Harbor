import Foundation

extension Harbor {
    /// Internal testing hook for intercepting network requests without using a customURLSession.
    @HRequestManagerActor
    static func setProtocolClasses(_ protocolClasses: [AnyClass]?) {
        HConfig.shared.protocolClasses = protocolClasses
        HRequestManager.invalidateURLSession()
    }
}
