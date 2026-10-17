//
//  HRequestManager+RESTSession.swift
//  Harbor
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation
import HarborCore

// MARK: - REST Sessions

extension HRequestManager {
    /// The session profile of a request: a GET request's cache type (or the default) selects
    /// the `URLCache`; other requests keep the configuration defaults.
    /// - Parameter request: The request.
    static func sessionProfile(for request: any HRequestBaseRequestProtocol) -> HSessionProfile {
        guard let getRequest = request as? any HGetRequestProtocol else { return .defaults }
        switch getRequest.cacheType ?? HRESTConfig.shared.cacheType {
        case .urlCache(let urlCache, let requestPolicy):
            return .urlCache(urlCache, requestPolicy)
        case .custom, .disabled:
            return .isolated
        }
    }

    /// The pooled session for the request. See `getURLSession(profile:)`.
    /// - Parameter request: The request whose cache type and configuration select the session.
    static func getURLSession(for request: any HRequestBaseRequestProtocol) -> URLSession {
        getURLSession(profile: sessionProfile(for: request))
    }

    /// Returns the session for the request and records that an attempt holds it. See
    /// `leaseURLSession(profile:)`.
    /// - Parameter request: The request whose cache type and configuration select the session.
    /// - Returns: The session to create the attempt's tasks on.
    static func leaseURLSession(for request: any HRequestBaseRequestProtocol) -> URLSession {
        leaseURLSession(profile: sessionProfile(for: request))
    }
}
