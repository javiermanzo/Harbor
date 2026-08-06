import Foundation
@testable import Harbor

enum HarborTestConfiguration {
    @HRequestManagerActor
    static func setLocalStubURLProtocol() {
        HConfig.shared.protocolClasses = [LocalStubURLProtocol.self]
        HRequestManager.invalidateURLSession()
    }
    
    @HRequestManagerActor
    static func resetLocalStubURLProtocol() {
        HConfig.shared.protocolClasses = nil
        HRequestManager.invalidateURLSession()
    }
}
