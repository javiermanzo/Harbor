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
/// Centralizes the LogBird instances the framework logs through (debug, security, and the
/// SSL/PKCS#12 diagnostics loggers it toggles) and the sensitive-key redaction policy, so
/// LogBird stays an internal implementation detail of Harbor instead of being configured
/// from `HConfig`, `Harbor` and the debug protocol independently.
///
/// Configure redaction through the public `Harbor.updateLogSensitiveKeys(_:)`
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
    /// via case-insensitive, separator-insensitive matching, so Harbor registers
    /// no extra keys on the LogBird logger; its own built-in HTTP credential keys
    /// live in `HRedactionPolicy.defaultSensitiveKeys` and are applied on top.
    ///
    /// Its `isEnabled` switch is driven by ``setLoggingEnabled(_:)``: LogBird disables
    /// recording outside DEBUG builds by default, so Harbor must flip it for
    /// `Harbor.setLoggingEnabled(true)` to take effect in release builds.
    static let logger = LogBird(subsystem: "com.harbor", category: "debugging")

    /// Logger for security warnings (configuration mistakes that silently weaken security).
    /// Always enabled and never toggled by ``setLoggingEnabled(_:)``, so the warnings are
    /// recorded in release builds and with debug logging disabled.
    static let securityLogger = LogBird(subsystem: "com.harbor", category: "security", config: LBConfig(isEnabled: true))

    /// Enables or disables Harbor's debug logging: updates the configuration flag and the
    /// recording switch of every LogBird logger Harbor writes diagnostics through (debug,
    /// SSL and PKCS#12). ``securityLogger`` is not affected.
    /// - Parameter enabled: Whether debug logs are recorded.
    static func setLoggingEnabled(_ enabled: Bool) {
        HConfig.shared.isLoggingEnabled = enabled
        for diagnosticsLogger in [logger, HURLSessionDelegate.logger, PKCS12.logger] {
            diagnosticsLogger.isEnabled = enabled
        }
    }

    // MARK: - Sensitive Keys

    /// The keys currently treated as sensitive by Harbor's logger.
    static var sensitiveKeys: Set<String> { logger.sensitiveKeys }

    /// Applies a sensitive-key update to Harbor's logger, mapping Harbor's
    /// public ``HLoggingSensitiveKeyAction`` to LogBird's action API.
    /// - Parameter action: The update to apply to the sensitive-key set (`.set`, `.add`, `.reset` or `.clear`).
    static func sensitiveKeys(_ action: HLoggingSensitiveKeyAction) {
        switch action {
        case .set(let keys): logger.sensitiveKeys(.set(keys))
        case .add(let keys): logger.sensitiveKeys(.add(keys))
        case .reset:         logger.sensitiveKeys(.reset)
        case .clear:         logger.sensitiveKeys(.clear)
        }
        HRedactionPolicy.setConfiguredKeys(logger.sensitiveKeys)
    }

    // MARK: - Logging

    /// Records a debug log entry through Harbor's logger if logging is enabled.
    /// - Parameters:
    ///   - message: The log message.
    ///   - extraMessages: Additional keyed messages (e.g. a cURL command).
    ///   - additionalInfo: Structured metadata; LogBird redacts sensitive keys.
    ///   - error: An error to attach.
    ///   - level: The severity. Default: `.debug`.
    ///   - file: The calling file, filled in by the compiler.
    ///   - function: The calling function, filled in by the compiler.
    ///   - line: The calling line, filled in by the compiler.
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

    /// Records a warning regardless of `isLoggingEnabled` and of the build configuration,
    /// through ``securityLogger``. Reserved for configuration mistakes that silently weaken
    /// security (e.g. SSL pinning not enforced), which must be visible in release builds too.
    /// - Parameters:
    ///   - message: The warning text.
    ///   - file: The calling file, filled in by the compiler.
    ///   - function: The calling function, filled in by the compiler.
    ///   - line: The calling line, filled in by the compiler.
    static func securityWarning(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        securityLogger.log(message, level: .warning, file: file, function: function, line: line)
    }
}
