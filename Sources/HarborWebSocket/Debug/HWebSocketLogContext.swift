//
//  HWebSocketLogContext.swift
//  HarborWebSocket
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation
import Harbor
import LogBird

/// Debug logging for one connection, created only for requests that opt in by conforming to
/// `HDebugRequestProtocol` (so a connection that did not opt in costs nothing). Every printed
/// value goes through `HRedactionPolicy`: handshake headers, query values and message payloads
/// are redacted unless `Harbor.setLogSensitiveValues(true)` is set, and payloads are truncated.
///
/// What is logged follows `debugType`: `.request` covers the handshake and sent messages,
/// `.response` the open event, received messages and the close; errors are logged for every
/// type, as for REST requests.
struct HWebSocketLogContext: Sendable {
    /// Maximum number of characters of a logged payload kept before truncation.
    private static let maxLoggedPayloadLength = 16 * 1024

    /// The request type name, printed with every entry.
    let requestName: String
    /// What the request asked to log.
    let debugType: HDebugRequestType

    /// Creates the context for a request, or `nil` when it did not opt into logging.
    /// - Parameter request: The endpoint description.
    init?<Request: HWebSocketRequestProtocol>(request: Request) {
        guard let debugRequest = request as? HDebugRequestProtocol else { return nil }
        requestName = String(describing: type(of: request))
        debugType = debugRequest.debugType
    }

    /// Whether handshake and sent messages are logged.
    private var logsRequest: Bool {
        debugType == .request || debugType == .requestAndResponse
    }

    /// Whether the open event, received messages and the close are logged.
    private var logsResponse: Bool {
        debugType == .response || debugType == .requestAndResponse
    }
}

// MARK: - Events

extension HWebSocketLogContext {
    /// Logs the handshake request about to be sent.
    /// - Parameters:
    ///   - urlRequest: The handshake request.
    ///   - subprotocols: The subprotocols offered.
    func logHandshake(urlRequest: URLRequest, subprotocols: [String]) async {
        guard logsRequest, await HLogger.isLoggingEnabled else { return }
        let policy = HRedactionPolicy.current
        var additionalInfo: [String: LBValue] = ["request": .string(requestName)]
        if let url = urlRequest.url {
            additionalInfo["url"] = .string(policy.redactedURLString(url))
        }
        if let headers = policy.redactedHeaders(urlRequest.allHTTPHeaderFields), !headers.isEmpty {
            additionalInfo["headerParameters"] = .string(Self.jsonString(headers))
        }
        if !subprotocols.isEmpty {
            additionalInfo["subprotocols"] = .string(subprotocols.joined(separator: ", "))
        }
        await HLogger.log("WebSocket handshake \(requestName)", additionalInfo: additionalInfo, level: .debug)
    }

    /// Logs a successful handshake.
    /// - Parameters:
    ///   - subprotocol: The subprotocol the server selected, if any.
    ///   - duration: The handshake duration in milliseconds.
    func logOpen(subprotocol: String?, duration: Double) async {
        guard logsResponse, await HLogger.isLoggingEnabled else { return }
        let additionalInfo: [String: LBValue] = [
            "request": .string(requestName),
            "subprotocol": .string(subprotocol ?? "none"),
            "duration": .string("\(String(format: "%.2f", duration))ms"),
        ]
        await HLogger.log("WebSocket open \(requestName)", additionalInfo: additionalInfo, level: .debug)
    }

    /// Logs a message sent by the app.
    /// - Parameter message: The sent message.
    func logSent(_ message: HWebSocketMessage) async {
        guard logsRequest, await HLogger.isLoggingEnabled else { return }
        await HLogger.log("WebSocket send \(requestName)", extraMessages: [LBExtraMessage(key: "Message", value: Self.printable(message))], additionalInfo: ["request": .string(requestName)], level: .debug)
    }

    /// Logs a message received from the server.
    /// - Parameter message: The received message.
    func logReceived(_ message: HWebSocketMessage) async {
        guard logsResponse, await HLogger.isLoggingEnabled else { return }
        await HLogger.log("WebSocket receive \(requestName)", extraMessages: [LBExtraMessage(key: "Message", value: Self.printable(message))], additionalInfo: ["request": .string(requestName)], level: .debug)
    }

    /// Logs the close of the connection.
    /// - Parameters:
    ///   - code: The close code.
    ///   - reason: The close reason, if any.
    ///   - initiatedLocally: Whether the app closed the connection.
    func logClose(code: URLSessionWebSocketTask.CloseCode, reason: Data?, initiatedLocally: Bool) async {
        guard logsResponse, await HLogger.isLoggingEnabled else { return }
        var additionalInfo: [String: LBValue] = [
            "request": .string(requestName),
            "closeCode": .int(code.rawValue),
            "initiatedBy": .string(initiatedLocally ? "client" : "server"),
        ]
        if let reason, let text = String(data: reason, encoding: .utf8) {
            additionalInfo["reason"] = .string(text)
        }
        await HLogger.log("WebSocket close \(requestName)", additionalInfo: additionalInfo, level: .debug)
    }

    /// Logs a failure. Errors are logged regardless of `debugType` so failures are never
    /// silently swallowed; only the logging-enabled gate applies.
    /// - Parameter error: The error.
    func logError(_ error: HWebSocketError) async {
        guard await HLogger.isLoggingEnabled else { return }
        // The description, not the raw value: a wrapped URLError's userInfo carries the full
        // URL, whose query string may hold a token.
        let description = error.errorDescription ?? String(describing: type(of: error))
        await HLogger.log("WebSocket error \(requestName)", extraMessages: [LBExtraMessage(key: "Error Type", value: description)], additionalInfo: ["request": .string(requestName)], level: .error)
    }
}

// MARK: - Formatting

extension HWebSocketLogContext {
    /// The printable, redacted and truncated form of a message payload. Binary payloads that
    /// are not UTF-8 are described by their size.
    /// - Parameter message: The message.
    private static func printable(_ message: HWebSocketMessage) -> String {
        let policy = HRedactionPolicy.current
        let text: String
        switch message {
        case .text(let value):
            text = value
        case .data(let data):
            guard let decoded = String(data: data, encoding: .utf8) else {
                return "<binary \(data.count) bytes>"
            }
            text = decoded
        }
        let redacted = policy.redactedBody(text) ?? "<\(text.utf8.count) bytes of unparseable JSON omitted>"
        guard redacted.count > maxLoggedPayloadLength else { return redacted }
        return String(redacted.prefix(maxLoggedPayloadLength)) + "… <truncated>"
    }

    /// A deterministic JSON rendering of a string dictionary.
    /// - Parameter dictionary: The dictionary.
    private static func jsonString(_ dictionary: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys, .withoutEscapingSlashes]),
              let string = String(data: data, encoding: .utf8) else {
            return "\(dictionary)"
        }
        return string
    }
}
