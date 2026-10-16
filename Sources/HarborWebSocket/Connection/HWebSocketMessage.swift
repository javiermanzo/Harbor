//
//  HWebSocketMessage.swift
//  HarborWebSocket
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation

/// A WebSocket message: a text frame (UTF-8) or a binary frame.
public enum HWebSocketMessage: Sendable {
    /// A text message.
    case text(String)
    /// A binary message.
    case data(Data)
}

// MARK: - Decoding

public extension HWebSocketMessage {
    /// Decodes the message payload as JSON. Text messages are decoded from their UTF-8 bytes,
    /// binary messages as-is.
    ///
    /// ```swift
    /// for try await message in socket.messages {
    ///     let event = try message.decode(ChatEvent.self)
    /// }
    /// ```
    /// - Parameters:
    ///   - type: The model type to decode.
    ///   - decoder: The decoder to use. Default: a new `JSONDecoder`.
    /// - Returns: The decoded model.
    /// - Throws: `HWebSocketError.codable` when the payload cannot be decoded.
    func decode<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) throws(HWebSocketError) -> T {
        do {
            return try decoder.decode(type, from: payload)
        } catch {
            throw .codable(modelName: "\(type)", error: error)
        }
    }

    /// The raw payload bytes: the UTF-8 bytes of a text message or the data of a binary message.
    var payload: Data {
        switch self {
        case .text(let text):
            return Data(text.utf8)
        case .data(let data):
            return data
        }
    }
}

// MARK: - URLSessionWebSocketTask.Message Bridging

extension HWebSocketMessage {
    /// Wraps a message received from `URLSessionWebSocketTask`.
    /// - Parameter message: The received message.
    init(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            self = .text(text)
        case .data(let data):
            self = .data(data)
        @unknown default:
            self = .data(Data())
        }
    }

    /// The message as `URLSessionWebSocketTask` sends it.
    var taskMessage: URLSessionWebSocketTask.Message {
        switch self {
        case .text(let text):
            return .string(text)
        case .data(let data):
            return .data(data)
        }
    }
}

// MARK: - Equatable, Hashable

extension HWebSocketMessage: Equatable, Hashable {}
