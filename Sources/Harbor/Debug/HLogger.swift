//
//  HLogger.swift
//  Harbor
//
//  Created by Javier Manzo on 01/08/2026.
//

import Foundation
import LogBird

/// Harbor's logging facade over LogBird.
///
/// Centralizes the single ``LogBird`` instance the framework logs through and
/// the sensitive-key redaction policy, so LogBird stays an internal
/// implementation detail of Harbor instead of being configured from `HConfig`,
/// `Harbor` and the debug protocol independently.
///
/// Configure redaction through the public `Harbor.loggingSensitiveKeys(_:)`
/// entry point, which takes an `HLoggingSensitiveKeyAction` (`.set`, `.add`,
/// `.reset`, `.clear`).
@HRequestManagerActor
enum HLogger {

    // MARK: - Logger

    /// Whether debug logging is currently enabled in Harbor's configuration.
    static var isLoggingEnabled: Bool {
        HConfig.shared.isLoggingEnabled
    }

    /// The single LogBird instance Harbor logs through, scoped to the
    /// `com.harbor` subsystem with a `debugging` category so entries are
    /// isolated in Console.app.
    ///
    /// It inherits LogBird's global default sensitive keys, whose expanded
    /// 2.1.0 set already covers HTTP auth fields (`authorization`, `auth`,
    /// `cookie`/`set-cookie`, `apikey`/`x-api-key`, `bearer`, `credentials`,
    /// `token`/`access_token`/`refresh_token`, `privatekey`/`private_key`, …)
    /// via case-insensitive, separator-insensitive matching, so Harbor does
    /// not register any keys of its own.
    static let logger = LogBird(subsystem: "com.harbor", category: "debugging")

    // MARK: - Sensitive Keys

    /// The keys currently treated as sensitive by Harbor's logger.
    static var sensitiveKeys: Set<String> { logger.sensitiveKeys }

    /// Applies a sensitive-key update to Harbor's logger, mapping Harbor's
    /// public ``HLoggingSensitiveKeyAction`` to LogBird's action API.
    static func sensitiveKeys(_ action: HLoggingSensitiveKeyAction) {
        switch action {
        case .set(let keys): logger.sensitiveKeys(.set(keys))
        case .add(let keys): logger.sensitiveKeys(.add(keys))
        case .reset:         logger.sensitiveKeys(.reset)
        case .clear:         logger.sensitiveKeys(.clear)
        }
    }

    // MARK: - Logging

    /// Records a debug log entry through Harbor's logger if logging is enabled.
    static func log(
        _ message: String? = nil,
        extraMessages: [LBExtraMessage]? = nil,
        additionalInfo: [String: LBValue]? = nil,
        error: Error? = nil,
        level: LBLogLevel = .debug,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        guard isLoggingEnabled else { return }

        logger.log(
            message,
            extraMessages: extraMessages,
            additionalInfo: additionalInfo,
            error: error,
            level: level,
            file: file,
            function: function,
            line: line
        )
    }
}
