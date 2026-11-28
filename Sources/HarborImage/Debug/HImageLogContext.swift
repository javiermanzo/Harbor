//
//  HImageLogContext.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation
import HarborCore

/// Debug logging of an image load, for requests that conform to `HDebugRequestProtocol`. URLs
/// are printed with Harbor's redaction (credentials in user info and sensitive query items);
/// nothing is logged when logging is disabled (`Harbor.setLoggingEnabled(_:)`).
@HRequestManagerActor
struct HImageLogContext {
    /// The redacted URL.
    private let url: String
    /// What the request asked to log.
    private let debugType: HDebugRequestType
    /// When the load started.
    private let start = Date()

    /// Creates the context, or `nil` when the request does not opt into logging.
    /// - Parameter resolved: The request.
    init?(resolved: HImageResolvedRequest) {
        guard let debugRequest = resolved.request as? HDebugRequestProtocol,
              debugRequest.debugType != .none,
              let url = resolved.urls.first else {
            return nil
        }
        self.debugType = debugRequest.debugType
        self.url = url.scheme?.lowercased() == "data"
            ? "data:<\(url.absoluteString.count) characters>"
            : HRedactionPolicy.current.redactedURLString(url, pathParameters: resolved.request.pathParameters)
    }
}

// MARK: - Logging

extension HImageLogContext {
    /// Logs the start of the load.
    func logStart() {
        guard debugType == .request || debugType == .requestAndResponse else { return }
        HLogger.log("HarborImage load: \(url)")
    }

    /// Logs the outcome of the load.
    /// - Parameter response: The response.
    func logFinish(_ response: HImageResponse) {
        guard debugType == .response || debugType == .requestAndResponse else { return }
        let duration = Int(Date().timeIntervalSince(start) * 1000)
        switch response {
        case .success(let result):
            HLogger.log("HarborImage loaded: \(url)",
                        additionalInfo: ["source": .string(result.source.rawValue),
                                         "format": .string(result.format.rawValue),
                                         "size": .string("\(result.image.width)x\(result.image.height)"),
                                         "duration_ms": .int(duration)])
        case .failure(let error):
            #if DEBUG
            HLogger.log("HarborImage failed: \(url)", error: error, level: .error)
            #endif
        }
    }
}
