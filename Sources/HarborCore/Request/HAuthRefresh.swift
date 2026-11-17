//
//  HAuthRefresh.swift
//  HarborCore
//
//  Created by Javier Manzo on 16/11/2026.
//

import Foundation

/// Outcome of evaluating a 401 response against the auth provider. The retry case carries
/// the refreshed authorization header, which the loop applies to the next attempt's
/// `URLRequest` without touching the request object.
package enum HAuthRefresh {
    /// The provider issued a different authorization header; retry with it applied.
    /// `notifiedProvider` tells whether `authFailed()` was called to obtain it.
    case retry(HAuthorizationHeader, notifiedProvider: Bool)
    /// No further attempt is possible; the request fails with `HRequestError.authNeeded`.
    case giveUp
}
